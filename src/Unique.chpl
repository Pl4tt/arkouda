/* unique finding and counting algorithms
 these are all based on dense histograms and sparse histograms(assoc domains/arrays)

 you could also use a sort if you got into a real bind with really
 large dense ranges of values and large arrays...

 *** need to factor in sparsity estimation somehow ***
 for example if (a.max-a.min > a.size) means that a's are sparse

 */
module Unique
{
    use ServerConfig;

    use Time only;
    use Math only;
    
    //use PrivateDist;
    //use HashedDist;
    use BlockDist;

    use SymArrayDmap;

    use CommAggregation;
    use RadixSortLSD;
    use SegmentedArray;
    use AryUtil;
    use Reflection;
    use Logging;

    private config const logLevel = ServerConfig.logLevel;
    const uLogger = new Logger(logLevel);

    /* // thresholds for different unique counting algorithms */
    /* var sBins = 2**10; // small-range maybe for using reduce intents on forall loops */
    /* var mBins = 2**20; // medium-range per-locale atomic hist */
    /* var lBins = 2**26 * numLocales; // large-range per-locale assoc array + global atomic hist */
    
    /* proc +(x: atomic int, y: atomic int) { */
    /*     return x.read() + y.read(); */
    /* } */
    
    /* proc +=(X: [?D] int, Y: [D] atomic int) { */
    /*     [i in D] {X[i] += Y[i].read();} */
    /* } */

    /* /\* */
    /* unique with global histogram */
    /* Returns a tuple: (UniqueValArray,UniqueValCountsArray) */
    /* which contains the unique values of a, along with the number of times each unique value appears in a */

    /* :arg a: Array of data to be processed */
    /* :type a: [] int */

    /* :arg aMin: Min value in array a */
    /* :type aMin: int */

    /* :arg aMax: Max value in array a */
    /* :type aMax: int */

    /* :returns: ([] int, [] int) */
    
    /* *\/ */
    /* proc uniqueGlobHist(a: [?aD] int, aMin: int, aMax: int) { */
    /*     // how many bins in histogram */
    /*     var bins = aMax-aMin+1; */

    /*     // distributed histogram domain */
    /*     var hD = makeDistDom(bins); */

    /*     // allocate atomic histogram */
    /*     var atomicHist: [hD] atomic int; */

    /*     // count into atomic histogram */
    /*     forall val in a { */
    /*         var bin = val - aMin; */
    /*         if val == aMax {bin = bins-1;} */
    /*         atomicHist[bin].add(1); */
    /*     } */

    /*     // integer truth/non-empty-bin array */
    /*     var itruth = makeDistArray(bins,int); */

    /*     // find non-empty bins in atomic histogram */
    /*     [(t,ae) in zip(itruth, atomicHist)] t = (ae.read() != 0):int; */

    /*     // calc indices of the non-zero count elements */
    /*     var iv: [hD] int = (+ scan itruth); */

    /*     // how many entries in unique array */
    /*     var pop = iv[iv.size-1]; */

    /*     // unique array */
    /*     var aV = makeDistArray(pop, int); */
    /*     // counts array */
    /*     var aC = makeDistArray(pop, int); */

    /*     // if value has non-zero histogram bin */
    /*     // put it into the unique array */
    /*     // and its count into the count array */
    /*     [i in hD] if (itruth[i] == 1) { */
    /*         aV[iv[i]-1] = i+aMin; */
    /*         aC[iv[i]-1] = atomicHist[i].read(); */
    /*     }// iv[i]-1 for zero base index */
        
    /*     return (aV, aC); */
    /* } */

    /* /\* */
    /* unique with per-locale histograms */
    /* Returns a tuple: (UniqueValArray,UniqueValCountsArray) */
    /* which contains the unique values of a, along with the number of times each unique value appears in a */

    /* :arg a: Array of data to be processed */
    /* :type a: [] int */

    /* :arg aMin: Min value in array a */
    /* :type aMin: int */

    /* :arg aMax: Max value in array a */
    /* :type aMax: int */

    /* :returns: ([] int, [] int) */
    
    /* *\/ */
    /* proc uniquePerLocHistGlobHist(a: [?aD] int, aMin: int, aMax: int) { */

    /*     // how many bin in histogram */
    /*     var bins = aMax-aMin+1; */

    /*     // allocate per-locale atomic histogram */
    /*     var atomicHist: [PrivateSpace] [0..#bins] atomic int; */

    /*     // count into per-locale private atomic histogram */
    /*     forall val in a { */
    /*         var bin = val - aMin; */
    /*         if val == aMax {bin = bins-1;} */
    /*         atomicHist[here.id][bin].add(1); */
    /*     } */

    /*     // distributed histogram domain */
    /*     var hD = makeDistDom(bins); */
        
    /*     // +reduce across per-locale histograms to get counts */
    /*     var globalHist: [hD] int = + reduce [i in PrivateSpace] atomicHist[i]; */

    /*     // integer truth/non-empty-bin array */
    /*     var itruth: [hD] int; */
        
    /*     // find non-empty bins */
    /*     [(t,e) in zip(itruth, globalHist)] t = (e != 0):int; */

    /*     // calc indices of the non-zero count elements */
    /*     var iv: [hD] int = (+ scan itruth); */

    /*     // how many entries in unique array */
    /*     var pop = iv[iv.size-1]; */

    /*     // unique array */
    /*     var aV = makeDistArray(pop, int); */
    /*     // counts array */
    /*     var aC = makeDistArray(pop, int); */

    /*     // if value has non-zero histogram bin */
    /*     // put value into the unique array */
    /*     // and value's count into the count array */
    /*     [i in hD] if (itruth[i] == 1) { */
    /*         aV[iv[i]-1] = i+aMin; */
    /*         aC[iv[i]-1] = globalHist[i]; */
    /*     }// iv[i]-1 for zero base index */
        
    /*     return (aV, aC); */
    /* } */

    /* /\* */
    /* use when unique values vary over a wide range and and are sparse */
    /* unique with per-locale assoc domains and arrays */
    /* global unique value histogram */
    
    /* Returns a tuple: (UniqueValArray,UniqueValCountsArray) */
    /* which contains the unique values of a, along with the number of times each unique value appears in a */

    /* :arg a: Array of data to be processed */
    /* :type a: [] int */

    /* :arg aMin: Min value in array a */
    /* :type aMin: int */

    /* :arg aMax: Max value in array a */
    /* :type aMax: int */

    /* :returns: ([] int, [] int) */
    /* *\/ */
    /* proc uniquePerLocAssocGlobHist(a: [?aD] int, aMin: int, aMax: int) { */

    /*     // per locale assoc domain of int to hold uniq values */
    /*     var uniqSet: [PrivateSpace] domain(int); */
    /*     [i in PrivateSpace] uniqSet[i].requestCapacity(100_000); */
        
    /*     // accumulate the uniq values into each locales domain of uniq values */
    /*     //[val in a] if !uniqSet[here.id].contains(val) {uniqSet[here.id] += val;} */
    /*     [val in a] uniqSet[here.id] += val; */

    /*     // how many bins in histogram */
    /*     var bins = aMax-aMin+1; */

    /*     // distributed histogram domain */
    /*     var hD = makeDistDom(bins); */

    /*     // allocate atomic histogram */
    /*     var atomicHist: [hD] atomic int; */
        
    /*     // calc local counts and then effectively +reduce uniqCounts to get global histogram */
    /*     coforall loc in Locales { */
    /*         on loc { */
    /*             var uniqCounts: [uniqSet[here.id]] atomic int; */

    /*             // count local part of array's values into per-locale private atomic counter set */
    /*             [i in a.localSubdomain()] uniqCounts[a[i]].add(1); */

    /*             // add local counts for unique value to global histogram */
    /*             [val in uniqSet[here.id]] atomicHist[val - aMin].add(uniqCounts[val].read()); */
    /*         } */
    /*     } */

    /*     // integer truth/non-empty-bin array */
    /*     var itruth = makeDistArray(bins,int); */

    /*     // find non-empty bins in atomic histogram */
    /*     [(t,ae) in zip(itruth, atomicHist)] t = (ae.read() != 0):int; */

    /*     // calc indices of the non-zero count elements */
    /*     var iv: [hD] int = (+ scan itruth); */

    /*     // how many entries in unique array */
    /*     var pop = iv[iv.size-1]; */

    /*     // unique array */
    /*     var aV = makeDistArray(pop, int); */
    /*     // counts array */
    /*     var aC = makeDistArray(pop, int); */

    /*     // if value has non-zero histogram bin */
    /*     // put it into the unique array */
    /*     // and its count into the count array */
    /*     [i in hD] if (itruth[i] == 1) { */
    /*         aV[iv[i]-1] = i+aMin; */
    /*         aC[iv[i]-1] = atomicHist[i].read(); */
    /*     }// iv[i]-1 for zero base index */

    /*     return (aV, aC); */
    /* } */

    /* /\* */
    /* use when unique value vary over a wide range and and are sparse */
    /* unique with per-locale assoc domains and arrays */

    /* Returns a tuple: (UniqueValArray,UniqueValCountsArray) */
    /* which contains the unique values of a, along with the number of times each unique value appears in a */

    /* :arg a: Array of data to be processed */
    /* :type a: [] int */

    /* :arg aMin: Min value in array a */
    /* :type aMin: int */

    /* :arg aMax: Max value in array a */
    /* :type aMax: int */

    /* :returns: ([] int, [] int) */
    /* *\/ */
    /* proc uniquePerLocAssocGlobAssoc(a: [?aD] int, aMin: int, aMax: int) { */

    /*     // per locale assoc domain of int to hold uniq values */
    /*     var uniqSet: [PrivateSpace] domain(int); */
    /*     [i in PrivateSpace] uniqSet[i].requestCapacity(100_000); */

    /*     // accumulate the uniq values into each locales domain of uniq values */
    /*     //[val in a] if !uniqSet[here.id].contains(val) {uniqSet[here.id] += val;} */
    /*     [val in a] uniqSet[here.id] += val; */
    /*     var numUniq = + reduce [i in PrivateSpace]  uniqSet[i].size; */
    /*     uLogger.debug(getModuleName(),getRoutineName(),getLineNumber(),
                                    "num unique vals upper bound = %t".format(numUniq));*/

    /*     // global assoc domain for global unique value set */
    /*     //var globalUniqSet: domain(int) dmapped Hashed(idxType=int); */
    /*     var globalUniqSet: domain(int); */
    /*     globalUniqSet.requestCapacity(100_000); */
        
    /*     // efectively +reduce(union-reduction) private uniqSet domians to get global uniqSet */
    /*     // what I really want is: */
    /*     //[i in PrivateSpace] globalUniqSet += uniqSet[i]; */
    /*     // or maybe even... */
    /*     for i in PrivateSpace {globalUniqSet += uniqSet[i];} */
    /*     // ok, well this... only one that works for HashedDist Assoc Domain */
    /*     //for loc in Locales { on loc { */
    /*     //         for val in uniqSet[here.id] {globalUniqSet += val;} */
    /*     //     } */
    /*     // } */
    /*     uLogger.debug(getModuleName(),getRoutineName(),getLineNumber(),
                                   "num unique vals = %t".format(globalUniqSet.size));*/

    /*     // allocate global uniqCounts over global set of uniq values */
    /*     var globalUniqCounts: [globalUniqSet] atomic int; */
        
    /*     // calc local counts and then effectively +reduce uniqCounts to get global uniqCount */
    /*     coforall loc in Locales { */
    /*         on loc { */
    /*             var uniqCounts: [uniqSet[here.id]] atomic int; */

    /*             // count locale part of array's values into per-locale private atomic counter set */
    /*             [i in a.localSubdomain()] uniqCounts[a[i]].add(1); */

    /*             // accumulate into global counters */
    /*             [val in uniqSet[here.id]] globalUniqCounts[val].add(uniqCounts[val].read()); */
    /*         } */
    /*     } */

    /*     // unique array */
    /*     var aV = makeDistArray(globalUniqSet.size, int); */
    /*     // counts array */
    /*     var aC = makeDistArray(globalUniqSet.size, int); */

    /*     var idx: atomic int; */
    /*     [val in globalUniqSet] { */
    /*         var i = idx.fetchAdd(1); // get index into dist array */
    /*         aV[i] = val; // copy unique value */
    /*         aC[i] = globalUniqCounts[val].read(); // copy count of unique value */
    /*     } */
        
    /*     // unlike the other versions */
    /*     // these are prob not sorted by value */
    /*     return (aV, aC); */
    /* } */
    
    /* /\* */
    /* use when unique value vary over a wide range and and are sparse */
    /* unique with per-locale assoc domains and arrays */

    /* Returns a tuple: (UniqueValArray,UniqueValCountsArray) */
    /* which contains the unique values of a, along with the number of times each unique value appears in a */

    /* :arg a: Array of data to be processed */
    /* :type a: [] int */

    /* :arg aMin: Min value in array a */
    /* :type aMin: int */

    /* :arg aMax: Max value in array a */
    /* :type aMax: int */

    /* :returns: ([] int, [] int) */
    /* *\/ */
    /* proc uniquePerLocAssocParUnsafeGlobAssocParUnsafe(a: [?aD] int, aMin: int, aMax: int) { */

    /*     // per locale assoc domain of int to hold uniq values */
    /*     // parSafe=false means NO modifying the domain in a parallel context */
    /*     var uniqSet: [PrivateSpace] domain(int, parSafe=false); */
    /*     [i in PrivateSpace] uniqSet[i].requestCapacity(100_000); */

    /*     // accumulate the uniq values into each locale's domain of uniq values */
    /*     coforall loc in Locales { */
    /*         on loc { */
    /*             // serially add to this locale's assoc domain of int */
    /*             for i in a.localSubdomain() { uniqSet[here.id] += a[i]; } */
    /*         } */
    /*     } */
        
    /*     // reduce counts across locales */
    /*     var numUniq = + reduce [i in PrivateSpace]  uniqSet[i].size; */
    /*     uLogger.debug(getModuleName(),getRoutineName(),getLineNumber(),
                                    "num unique vals upper bound = %t".format(numUniq));*/

    /*     // global assoc domain for global unique value set */
    /*     // parSafe=false means NO modifying the domain in a parallel context */
    /*     var globalUniqSet: domain(int, parSafe=false); */
    /*     globalUniqSet.requestCapacity(100_000); */
        
    /*     // efectively +reduce(union-reduction) private uniqSet domians to get global uniqSet */
    /*     // serial iteration because parSafe=false */
    /*     for loc in Locales { */
    /*         on loc { */
    /*             for val in uniqSet[here.id] {globalUniqSet += val;} */
    /*         } */
    /*     } */
    /*     uLogger.debug(getModuleName(),getRoutineName(),getLineNumber(),
                                    "num unique vals = %t".format(globalUniqSet.size));*/

    /*     // allocate global uniqCounts over global set of uniq values */
    /*     var globalUniqCounts: [globalUniqSet] atomic int; */
        
    /*     // calc local counts and then effectively +reduce uniqCounts to get global uniqCount */
    /*     coforall loc in Locales { */
    /*         on loc { */
    /*             var uniqCounts: [uniqSet[here.id]] atomic int; */

    /*             // count locale part of array's values into per-locale private atomic counter set */
    /*             [i in a.localSubdomain()] uniqCounts[a[i]].add(1); */

    /*             // accumulate into global counters */
    /*             [val in uniqSet[here.id]] globalUniqCounts[val].add(uniqCounts[val].read()); */
    /*         } */
    /*     } */

    /*     // unique array */
    /*     var aV = makeDistArray(globalUniqSet.size, int); */
    /*     // counts array */
    /*     var aC = makeDistArray(globalUniqSet.size, int); */

    /*     //for (val,i) in zip(globalUniqSet.sorted(), 0..) { */
    /*     for (val,i) in zip(globalUniqSet, 0..) { */
    /*         aV[i] = val; // copy unique value */
    /*         aC[i] = globalUniqCounts[val].read(); // copy count of unique value */
    /*     } */
        
    /*     return (aV, aC); */
    /* } */

   /*
    sorting based unique finding procedure

    Returns a tuple: (UniqueValArray,UniqueValCountsArray)
    which contains the unique values of a, along with the number of times each unique value appears in a

    :arg a: Array of data to be processed
    :type a: [] int

    :returns: ([] int, [] int)
    */
    proc uniqueSort(a: [?aD] ?eltType, param needCounts = true) throws {
        if (aD.size == 0) {
            try! uLogger.debug(getModuleName(),getRoutineName(),getLineNumber(),"zero size");
            var u = makeDistArray(0, eltType);
            if (needCounts) {
                var c = makeDistArray(0, int);
                return (u,c);
            } else {
                return u;
            }
        } 

        var sorted = radixSortLSD_keys(a);
        return uniqueFromSorted(sorted, needCounts);
    }

    proc uniqueSortWithInverse(a: [?aD] ?eltType) throws {
        if (aD.size == 0) {
            try! uLogger.debug(getModuleName(),getRoutineName(),getLineNumber(),"zero size");
            var u = makeDistArray(0, eltType);
            var c = makeDistArray(0, int);
            var inv = makeDistArray(0, int);
            return (u, c, inv);
        }
        var sorted: [aD] eltType;
        var perm: [aD] int;
        forall (s, p, sp) in zip(sorted, perm, radixSortLSD(a)) {
          (s, p) = sp;
        }
        var (u, c) = uniqueFromSorted(sorted);
        // check there's enough room to create a copy for scan and throw if creating a copy would go over memory limit
        overMemLimit(numBytes(int) * c.size);
        var segs = (+ scan c) - c;
        var bcast: [aD] int;
        forall s in segs with (var agg = newDstAggregator(int)) {
            agg.copy(bcast[s], 1);
        }
        bcast[0] = 0;
        // check there's enough room to create a copy for scan and throw if creating a copy would go over memory limit
        overMemLimit(numBytes(int) * bcast.size);
        bcast = (+ scan bcast);
        var inv: [aD] int;
        forall (p, b) in zip(perm, bcast) with (var agg = newDstAggregator(int)) {
            agg.copy(inv[p], b);
        }
        return (u, c, inv);
    }
    
    proc uniqueFromSorted(sorted: [?aD] ?eltType, param needCounts = true) throws {
        var truth: [aD] bool;
        truth[0] = true;
        [(t, s, i) in zip(truth, sorted, aD)] if i > aD.low { t = (sorted[i-1] != s); }
        var allUnique: int = + reduce truth;
        if (allUnique == aD.size) {
           try!  uLogger.debug(getModuleName(),getRoutineName(),getLineNumber(),
                                    "early out already unique");
            var u = makeDistArray(aD.size, eltType);
            u = sorted; // array is already unique
            if (needCounts) {
                var c = makeDistArray(aD.size, int);
                c = 1;
                return (u,c);
            } else {
                return u;
            }
        }
        // +scan to compute segment position... 1-based because of inclusive-scan
        // check there's enough room to create a copy for scan and throw if creating a copy would go over memory limit
        overMemLimit(numBytes(int) * truth.size);
        var iv: [truth.domain] int = (+ scan truth);
        // compute how many segments
        var pop = iv[iv.size-1];
        try! uLogger.debug(getModuleName(),getRoutineName(),getLineNumber(),"pop = %t".format(pop));

        var segs = makeDistArray(pop, int);
        var ukeys = makeDistArray(pop, eltType);
        
        // segment position... 1-based needs to be converted to 0-based because of inclusive-scan
        // where ever a segment break (true value) is... that index is a segment start index
        forall i in truth.domain with (var agg = newDstAggregator(int)) {
          if (truth[i] == true) {
            var idx = i; 
            agg.copy(segs[iv[i]-1], idx);
          }
        }
        // pull out the first key in each segment as a unique key
        // unique keys guaranteed to be sorted because keys are sorted
        forall (i, uk, seg) in zip(segs.domain, ukeys, segs) with (var agg = newSrcAggregator(eltType)) {
          agg.copy(uk, sorted[seg]);
        }
        // [i in segs.domain] ukeys[i] = sorted[segs[i]];

        if (needCounts) {
            var counts = makeDistArray(pop, int);
            // calc counts of each unique key using segs
            forall i in segs.domain {
                if i < segs.domain.high {
                    counts[i] = segs[i+1] - segs[i];
                }
                else
                {
                    counts[i] = sorted.domain.high+1 - segs[i];
                }
            }
            return (ukeys,counts);
        } else {
            return ukeys;
        }
    }

    proc uniqueGroup(str: SegString, returnInverse = false) throws {
        if (str.size == 0) {
            uLogger.debug(getModuleName(),getRoutineName(),getLineNumber(),"zero size");
            var uo = makeDistArray(0, int);
            var uv = makeDistArray(0, uint(8));
            var c = makeDistArray(0, int);
            var inv = makeDistArray(0, int);
            return (uo, uv, c, inv);
        }
        const aD = str.offsets.aD;
        var invD: aD.type;
        if returnInverse {
          invD = aD;
        } else {
          invD = {0..-1};
        }
        var inv: [invD] int;
        var truth: [aD] bool;
        var perm: [aD] int;
        if SegmentedArrayUseHash {
          var hashes = str.hash();
          var sorted: [aD] 2*uint;
          forall (s, p, sp) in zip(sorted, perm, radixSortLSD(hashes)) {
            (s, p) = sp;
          }
          truth[0] = true;
          [(t, s, i) in zip(truth, sorted, aD)] if i > aD.low { t = (sorted[i-1] != s); }
        } else {
          var soff: [aD] int;
          var sval: [str.values.aD] uint(8);
          perm = str.argsort();
          (soff, sval) = str[perm];
          truth[0] = true;
          // truth[{1..aD.high}] = sorted[0..aD.high-1] != sorted[1..aD.high];
          forall (t, o, idx) in zip(truth, soff, aD) {
            if (idx > aD.low) {
              const llen = o - soff[idx-1] - 1;
              const rlen = if (idx < aD.high) then (soff[idx+1] - 1 - o) else (sval.domain.high - o);
              if (llen != rlen) {
                // If lengths differ, this is a step
                t = true;
              } else {
                var allEqual = true;
                for pos in 0..#llen {
                  if (sval[soff[idx-1]+pos] != sval[o+pos]) {
                    allEqual = false;
                    break;
                  }
                }
                // If lengths equal but bytes differ, this is a step
                if !allEqual {
                  t = true;
                }
              }
            }
          }
        }
        var (uo, uv, c) = uniqueFromTruth(str, perm, truth);
        if returnInverse {
            // check there's enough room to create a copy for scan and throw if creating a copy would go over memory limit
            overMemLimit(numBytes(int) * c.size);
            var segs = (+ scan c) - c;
            var bcast: [invD] int;
            forall s in segs with (var agg = newDstAggregator(int)) {
                agg.copy(bcast[s], 1);
            }
            bcast[0] = 0;
            // check there's enough room to create a copy for scan and throw if creating a copy would go over memory limit
            overMemLimit(numBytes(int) * bcast.size);
            bcast = (+ scan bcast);
            forall (p, b) in zip(perm, bcast) with (var agg = newDstAggregator(int)) {
                agg.copy(inv[p], b);
            }
        }
        return (uo, uv, c, inv);
    }

    proc uniqueFromTruth(str: SegString, perm: [?aD] int, truth: [aD] bool) throws {
        var allUnique: int = + reduce truth;
        if (allUnique == aD.size) {
            uLogger.debug(getModuleName(),getRoutineName(),getLineNumber(),"early out already unique");
            var uo = makeDistArray(aD.size, int);
            var uv = makeDistArray(str.nBytes, uint(8));
            var c = makeDistArray(aD.size, int);
            uo = str.offsets.a; // a is already unique
            uv = str.values.a;
            c = 1; // c counts are all 1
            return (uo, uv, c);
        }
        // +scan to compute segment position... 1-based because of inclusive-scan
        // check there's enough room to create a copy for scan and throw if creating a copy would go over memory limit
        overMemLimit(numBytes(int) * truth.size);
        var iv: [aD] int = (+ scan truth);
        // compute how many segments
        var pop = iv[iv.size-1];
        uLogger.debug(getModuleName(),getRoutineName(),getLineNumber(),"pop = %t".format(pop));

        var segs = makeDistArray(pop, int);
        var counts = makeDistArray(pop, int);
        var uinds = makeDistArray(pop, int);
        
        // segment position... 1-based needs to be converted to 0-based because of inclusive-scan
        // where ever a segment break (true value) is... that index is a segment start index
        forall i in aD with (var agg = newDstAggregator(int)) {
          if (truth[i] == true) {
            var idx = i;
            agg.copy(segs[iv[i]-1], idx);
          }
        }
        // pull out the first key in each segment as a unique key
        // unique keys guaranteed to be sorted because keys are sorted
        forall (u, s) in zip(uinds, segs) with (var agg = newSrcAggregator(int)) {
          agg.copy(u, perm[s]); // uinds[i] = perm[segs[i]];
        }
        // Gather the unique offsets and values (byte buffers)
        var (uo, uv) = str[uinds];
        // calc counts of each unique key using segs
        forall i in segs.domain {
            if i < segs.domain.high {
                counts[i] = segs[i+1] - segs[i];
            }
            else
            {
                counts[i] = aD.high+1 - segs[i];
            }
        }

        return (uo, uv, counts);
    }
}

