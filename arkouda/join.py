from typing import cast, Tuple, Union
from typeguard import typechecked
import numpy as np  # type: ignore
from arkouda.client import generic_msg
from arkouda.dtypes import int64 as akint64
from arkouda.dtypes import resolve_scalar_dtype, NUMBER_FORMAT_STRINGS
from arkouda.pdarrayclass import pdarray, create_pdarray
from arkouda.pdarraycreation import array, ones, zeros, zeros_like, arange
from arkouda.pdarraysetops import concatenate, in1d, intersect1d
from arkouda.alignment import right_align
from arkouda.numeric import cumsum
from arkouda.groupbyclass import GroupBy, broadcast

__all__ = ["join_on_eq_with_dt"]

predicates = {"true_dt": 0, "abs_dt": 1, "pos_dt": 2}


@typechecked
def join_on_eq_with_dt(a1: pdarray, a2: pdarray, t1: pdarray,
                       t2: pdarray, dt: Union[int, np.int64], pred: str,
                       result_limit: Union[int, np.int64] = 1000) -> Tuple[pdarray, pdarray]:
    """
    Performs an inner-join on equality between two integer arrays where
    the time-window predicate is also true

    Parameters
    ----------
    a1 : pdarray, int64
        pdarray to be joined
    a2 : pdarray, int64
        pdarray to be joined
    t1 : pdarray
        timestamps in millis corresponding to the a1 pdarray
    t2 : pdarray,
        timestamps in millis corresponding to the a2 pdarray
    dt : Union[int,np.int64]
        time delta
    pred : str
        time window predicate
    result_limit : Union[int,np.int64]
        size limit for returned result

    Returns
    -------
    result_array_one : pdarray, int64
        a1 indices where a1 == a2
    result_array_one : pdarray, int64
        a2 indices where a2 == a1

    Raises
    ------
    TypeError
        Raised if a1, a2, t1, or t2 is not a pdarray, or if dt or
        result_limit is not an int
    ValueError
        if a1, a2, t1, or t2 dtype is not int64, pred is not
        'true_dt', 'abs_dt', or 'pos_dt', or result_limit is < 0
    """
    if not (a1.dtype == akint64):
        raise ValueError("a1 must be int64 dtype")

    if not (a2.dtype == akint64):
        raise ValueError("a2 must be int64 dtype")

    if not (t1.dtype == akint64):
        raise ValueError("t1 must be int64 dtype")

    if not (t2.dtype == akint64):
        raise ValueError("t2 must be int64 dtype")

    if not (pred in predicates.keys()):
        raise ValueError("pred must be one of ", predicates.keys())

    if result_limit < 0:
        raise ValueError('the result_limit must 0 or greater')

    # format numbers for request message
    dttype = resolve_scalar_dtype(dt)
    dtstr = NUMBER_FORMAT_STRINGS[dttype].format(dt)
    predtype = resolve_scalar_dtype(predicates[pred])
    predstr = NUMBER_FORMAT_STRINGS[predtype].format(predicates[pred])
    result_limittype = resolve_scalar_dtype(result_limit)
    result_limitstr = NUMBER_FORMAT_STRINGS[result_limittype]. \
        format(result_limit)
    # groupby on a2
    g2 = GroupBy(a2)
    # pass result into server joinEqWithDT operation
    repMsg = generic_msg(cmd="joinEqWithDT", args="{} {} {} {} {} {} {} {} {}". \
                         format(a1.name,
                                cast(pdarray, g2.segments).name,  # type: ignore
                                cast(pdarray, g2.unique_keys).name,  # type: ignore
                                g2.permutation.name,
                                t1.name,
                                t2.name,
                                dtstr, predstr, result_limitstr))
    # create pdarrays for results
    resIAttr, resJAttr = cast(str, repMsg).split("+")
    resI = create_pdarray(resIAttr)
    resJ = create_pdarray(resJAttr)
    return (resI, resJ)


def gen_ranges(starts, ends):
    """ Generate a segmented array of variable-length, contiguous
    ranges between pairs of start- and end-points.

    Parameters
    ----------
    starts : pdarray, int64
        The start value of each range
    ends : pdarray, int64
        The end value (exclusive) of each range

    Returns
    -------
    segments : pdarray, int64
        The starting index of each range in the resulting array
    ranges : pdarray, int64
        The actual ranges, flattened into a single array
    """
    if starts.size != ends.size:
        raise ValueError("starts and ends must be same size")
    if starts.size == 0:
        return zeros(0, dtype=akint64), zeros(0, dtype=akint64)
    lengths = ends - starts
    if not (lengths > 0).all():
        raise ValueError("all ends must be greater than starts")
    segs = cumsum(lengths) - lengths
    totlen = lengths.sum()
    slices = ones(totlen, dtype=akint64)
    diffs = concatenate((array([starts[0]]),
                         starts[1:] - starts[:-1] - lengths[:-1] + 1))
    slices[segs] = diffs
    return segs, cumsum(slices)


def compute_join_size(a, b):
    '''Compute the internal size of a hypothetical join between a and b. Returns
    both the number of elements and number of bytes required for the join.
    '''
    bya = GroupBy(a)
    ua, asize = bya.count()
    byb = GroupBy(b)
    ub, bsize = byb.count()
    afact = asize[in1d(ua, ub)]
    bfact = bsize[in1d(ub, ua)]
    nelem = (afact * bfact).sum()
    nbytes = 3 * 8 * nelem
    return nelem, nbytes


def inner_join(left, right, wherefunc=None, whereargs=None):
    '''Perform inner join on values in <left> and <right>,
    using conditions defined by <wherefunc> evaluated on
    <whereargs>, returning indices of left-right pairs.

    Parameters
    ----------
    left : pdarray(int64)
        The left values to join
    right : pdarray(int64)
        The right values to join
    wherefunc : function, optional
        Function that takes two pdarray arguments and returns
        a pdarray(bool) used to filter the join. Results for
        which wherefunc is False will be dropped.
    whereargs : 2-tuple of pdarray
        The two pdarray arguments to wherefunc

    Returns
    -------
    leftInds : pdarray(int64)
        The left indices of pairs that meet the join condition
    rightInds : pdarray(int64)
        The right indices of pairs that meet the join condition

    Notes
    -----
    The return values satisfy the following assertions

    `assert (left[leftInds] == right[rightInds]).all()`
    `assert wherefunc(whereargs[0][leftInds], whereargs[1][rightInds]).all()`

    '''
    from inspect import signature
    sample = min((left.size, right.size, 5))
    if wherefunc is not None:
        if len(signature(wherefunc).parameters) != 2:
            raise ValueError("wherefunc must be a function that accepts exactly two arguments")
        if whereargs is None or len(whereargs) != 2:
            raise ValueError("whereargs must be a 2-tuple with left and right arg arrays")
        if whereargs[0].size != left.size:
            raise ValueError("Left whereargs must be same size as left join values")
        if whereargs[1].size != right.size:
            raise ValueError("Right whereargs must be same size as right join values")
        try:
            _ = wherefunc(whereargs[0][:sample], whereargs[1][:sample])
        except Exception as e:
            raise ValueError("Error evaluating wherefunc") from e

    # Need dense 0-up right index, to filter out left not in right
    keep, (denseLeft, denseRight) = right_align(left, right)
    if keep.sum() == 0:
        # Intersection is empty
        return zeros(0, dtype=akint64), zeros(0, dtype=akint64)
    keep = arange(keep.size)[keep]
    # GroupBy right
    byRight = GroupBy(denseRight)
    # Get segment boundaries (starts, ends) of right for each left item
    rightSegs = concatenate((byRight.segments, array([denseRight.size])))
    starts = rightSegs[denseLeft]
    ends = rightSegs[denseLeft + 1]
    fullSize = (ends - starts).sum()
    # print(f"{left.size+right.size:,} input rows --> {fullSize:,} joins ({fullSize/(left.size+right.size):.1f} x) ")
    # gen_ranges for gather of right items
    fullSegs, ranges = gen_ranges(starts, ends)
    # Evaluate where clause
    if wherefunc is None:
        filtRanges = ranges
        filtSegs = fullSegs
        keep12 = keep
    else:
        # Gather right whereargs
        rightWhere = whereargs[1][byRight.permutation][ranges]
        # Expand left whereargs
        leftWhere = broadcast(fullSegs, whereargs[0][keep], ranges.size)
        # Evaluate wherefunc and filter ranges, recompute segments
        whereSatisfied = wherefunc(leftWhere, rightWhere)
        filtRanges = ranges[whereSatisfied]
        scan = cumsum(whereSatisfied) - whereSatisfied
        filtSegsWithZeros = scan[fullSegs]
        filtSegSizes = concatenate((filtSegsWithZeros[1:] - filtSegsWithZeros[:-1],
                                    array([whereSatisfied.sum() - filtSegsWithZeros[-1]])))
        keep2 = (filtSegSizes > 0)
        filtSegs = filtSegsWithZeros[keep2]
        keep12 = keep[keep2]
    # Gather right inds and expand left inds
    rightInds = byRight.permutation[filtRanges]
    leftInds = broadcast(filtSegs, arange(left.size)[keep12], filtRanges.size)
    return leftInds, rightInds


# def inner_join2(left, right, wherefunc=None, whereargs=None, forceDense=False):
#     '''Perform inner join on values in <left> and <right>,
#     using conditions defined by <wherefunc> evaluated on
#     <whereargs>, returning indices of left-right pairs.
#
#     Parameters
#     ----------
#     left : pdarray(int64)
#         The left values to join
#     right : pdarray(int64)
#         The right values to join
#     wherefunc : function, optional
#         Function that takes two pdarray arguments and returns
#         a pdarray(bool) used to filter the join. Results for
#         which wherefunc is False will be dropped.
#     whereargs : 2-tuple of pdarray
#         The two pdarray arguments to wherefunc
#
#     Returns
#     -------
#     leftInds : pdarray(int64)
#         The left indices of pairs that meet the join condition
#     rightInds : pdarray(int64)
#         The right indices of pairs that meet the join condition
#
#     Notes
#     -----
#     The return values satisfy the following assertions
#
#     `assert (left[leftInds] == right[rightInds]).all()`
#     `assert wherefunc(whereargs[0][leftInds], whereargs[1][rightInds]).all()`
#
#     '''
#     if not isinstance(left, pdarray) or left.dtype != akint64 or not isinstance(right,
#                                                                                 pdarray) or right.dtype != akint64:
#         raise ValueError("left and right must be pdarray(int64)")
#     if wherefunc is not None:
#         from inspect import signature
#         sample = min((left.size, right.size, 5))
#         if len(signature(wherefunc).parameters) != 2:
#             raise ValueError("wherefunc must be a function that accepts exactly two arguments")
#         if whereargs is None or len(whereargs) != 2:
#             raise ValueError("whereargs must be a 2-tuple with left and right arg arrays")
#         if whereargs[0].size != left.size:
#             raise ValueError("Left whereargs must be same size as left join values")
#         if whereargs[1].size != right.size:
#             raise ValueError("Right whereargs must be same size as right join values")
#         try:
#             _ = wherefunc(whereargs[0][:sample], whereargs[1][:sample])
#         except Exception as e:
#             raise ValueError("Error evaluating wherefunc") from e
#     # Only join on intersection
#     inter = intersect1d(left, right)
#     # Indices of left values present in intersection
#     leftInds = arange(left.size)[in1d(left, inter)]
#     # Left vals in intersection
#     leftFilt = left[leftInds]
#     # Indices of right vals present in inter
#     rightInds = arange(right.size)[in1d(right, inter)]
#     # Right vals in inter
#     rightFilt = right[rightInds]
#     byLeft = GroupBy(leftFilt)
#     byRight = GroupBy(rightFilt)
#     maxVal = inter.max()
#     if forceDense or maxVal > 3 * (left.size + right.size):
#         # Remap intersection to dense, 0-up codes
#         # Replace left values with dense codes
#         uniqLeftVals = byLeft.unique_keys
#         uniqLeftCodes = arange(inter.size)[in1d(inter, uniqLeftVals)]
#         leftCodes = zeros_like(leftFilt) - 1
#         leftCodes[byLeft.permutation] = byLeft.broadcast(uniqLeftCodes, permute=False)
#         # Replace right values with dense codes
#         uniqRightVals = byRight.unique_keys
#         uniqRightCodes = arange(inter.size)[in1d(inter, uniqRightVals)]
#         rightCodes = zeros_like(rightFilt) - 1
#         rightCodes[byRight.permutation] = byRight.broadcast(uniqRightCodes, permute=False)
#         countSize = inter.size
#     else:
#         uniqLeftCodes = byLeft.unique_keys
#         uniqRightCodes = byRight.unique_keys
#         leftCodes = leftFilt
#         rightCodes = rightFilt
#         countSize = maxVal + 1
#     # Expand indices to product domain
#     # First count occurrences of each code in left and right
#     leftCounts = zeros(countSize, dtype=akint64)
#     leftCounts[uniqLeftCodes] = byLeft.count()[1]
#     rightCounts = zeros(countSize, dtype=akint64)
#     rightCounts[uniqRightCodes] = byRight.count()[1]
#     # Repeat each left index as many times as that code occurs in right
#     prodLeft = rightCounts[leftCodes]
#     leftFullInds = broadcast(cumsum(prodLeft) - prodLeft, leftInds, prodLeft.sum())
#     prodRight = leftCounts[rightCodes]
#     rightFullInds = broadcast(cumsum(prodRight) - prodRight, rightInds, prodRight.sum())
#     # Evaluate where clause
#     if wherefunc is None:
#         return leftFullInds, rightFullInds
#     else:
#         # Gather whereargs
#         leftWhere = whereargs[0][leftFullInds]
#         rightWhere = whereargs[1][rightFullInds]
#         # Evaluate wherefunc and filter ranges, recompute segments
#         whereSatisfied = wherefunc(leftWhere, rightWhere)
#         return leftFullInds[whereSatisfied], rightFullInds[whereSatisfied]
