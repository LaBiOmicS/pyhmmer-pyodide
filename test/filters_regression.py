"""Regression test for the SIMD pre-filters (SSV/MSV, Viterbi) of pyhmmer on WebAssembly.

The bug this guards against: HMMER converts negative float costs to bytes with `(uint8_t) sc`.
On x86 the value wraps around; on WebAssembly it saturates to 0, every MSV/SSV score collapses,
and the pipeline silently reports no hits. Here the default pipeline (filters on) must report
the same strong hits, with the same scores, as a pipeline with every filter disabled.
"""
import importlib.resources
import sys

import pyhmmer
from pyhmmer.easel import SequenceFile
from pyhmmer.plan7 import HMMFile, Pipeline

DATA = importlib.resources.files("pyhmmer.tests").joinpath("data")
STRONG = 1e-10


def strong(top):
    return {(h.name.decode() if isinstance(h.name, bytes) else h.name, round(h.score, 3)) for h in top if h.evalue < STRONG}


def check_protein(hmm_name, seqs_name):
    with HMMFile(str(DATA / "hmms" / "txt" / hmm_name)) as f:
        hmm = f.read()
    with SequenceFile(str(DATA / "seqs" / seqs_name), digital=True, alphabet=hmm.alphabet) as f:
        seqs = f.read_block()
    on = strong(Pipeline(hmm.alphabet).search_hmm(hmm, seqs))
    off = strong(Pipeline(hmm.alphabet, bias_filter=False, F1=1.0, F2=1.0, F3=1.0).search_hmm(hmm, seqs))
    return on, off


def check_dna(hmm_name, seqs_name):
    with HMMFile(str(DATA / "hmms" / "txt" / hmm_name)) as f:
        hmm = f.read()
    with SequenceFile(str(DATA / "seqs" / seqs_name), digital=True, alphabet=hmm.alphabet) as f:
        seqs = f.read_block()
    on = strong(next(pyhmmer.hmmer.nhmmer([hmm], seqs, cpus=1)))
    off = strong(next(pyhmmer.hmmer.nhmmer([hmm], seqs, cpus=1, bias_filter=False, F1=1.0, F2=1.0, F3=1.0)))
    return on, off


CASES = [
    ("protein", "PF02826.hmm", "938293.PRJEB85.HG003687.faa", check_protein),
    ("protein", "LuxC.hmm", "LuxC.faa", check_protein),
    ("dna", "RF00001.hmm", "1390.SAMEA104415756.OFHT01000024.fna", check_dna),
]

failed = 0
for kind, hmm_name, seqs_name, fn in CASES:
    on, off = fn(hmm_name, seqs_name)
    ok = on == off and len(off) > 0
    failed += not ok
    print(f"{'OK  ' if ok else 'FAIL'} {kind:7} {hmm_name:18} {seqs_name:40} strong hits: filters on {len(on)}, off {len(off)}")
print("filters regression:", "PASSED" if not failed else f"{failed} FAILED")
sys.exit(1 if failed else 0)
