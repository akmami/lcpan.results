#!/usr/bin/env python3
import sys
import re
from collections import defaultdict

# Matches perf report "top" lines:
#   6.67%  lcpan  liblcptools.so  [.] dct_worker
LINE_RE = re.compile(
    r"^\s*([0-9]+(?:\.[0-9]+)?)%\s+(\S+)\s+(\S+)\s+(.+?)\s*$"
)

def main():
    import argparse
    p = argparse.ArgumentParser(
        description="Sum perf report overhead by (Command, Shared Object) tuple."
    )
    p.add_argument("file", nargs="?", help="Input file (default: stdin)")
    p.add_argument("--symbols", action="store_true",
                   help="Also print top symbols per (Command, Shared Object).")
    p.add_argument("--top", type=int, default=30,
                   help="Top N tuples to print (default: 30). Use 0 for all.")
    p.add_argument("--top-syms", type=int, default=5,
                   help="Top N symbols per tuple (default: 5).")
    args = p.parse_args()

    fh = open(args.file, "r", encoding="utf-8", errors="replace") if args.file else sys.stdin

    tuple_sum = defaultdict(float)                 # (cmd, so) -> overhead
    tuple_sym_sum = defaultdict(lambda: defaultdict(float))  # (cmd, so) -> symbol -> overhead

    for line in fh:
        m = LINE_RE.match(line)
        if not m:
            continue
        overhead = float(m.group(1))
        cmd = m.group(2)
        so = m.group(3)
        rest = m.group(4)

        # Symbol is usually after "[.]" or "[k]" etc. If not found, keep rest.
        # Examples: "[.] dct_worker", "[k] schedule", "[unknown] ..."
        sym = rest
        m2 = re.search(r"\]\s*(.+)$", rest)
        if m2:
            sym = m2.group(1).strip()

        key = (cmd, so)
        tuple_sum[key] += overhead
        tuple_sym_sum[key][sym] += overhead

    if fh is not sys.stdin:
        fh.close()

    items = sorted(tuple_sum.items(), key=lambda kv: kv[1], reverse=True)
    if args.top and args.top > 0:
        items = items[:args.top]

    grand_total = sum(tuple_sum.values())

    print("Overhead%   Command        Shared Object")
    print("---------   ------------   ------------------------------")
    for (cmd, so), ov in items:
        print(f"{ov:8.2f}%   {cmd:<12}   {so}")
        if args.symbols:
            syms = sorted(tuple_sym_sum[(cmd, so)].items(), key=lambda kv: kv[1], reverse=True)
            syms = syms[:args.top_syms] if args.top_syms and args.top_syms > 0 else syms
            for sym, sov in syms:
                print(f"           └─ {sov:6.2f}%  {sym}")
    print("---------")
    print(f"Sum of extracted overhead lines: {grand_total:.2f}%")
    print("(Note: perf report overhead lines you extract may not sum to 100% if the input is partial/filtered.)")

if __name__ == "__main__":
    main()

# #!/usr/bin/env python3
# import sys
# import re
# from collections import defaultdict

# LINE_RE = re.compile(
#     r"^\s*([0-9]+(?:\.[0-9]+)?)%\s+\S+\s+(\S+)"
# )

# def main():
#     import argparse
#     p = argparse.ArgumentParser(description="Sum perf overhead by Shared Object")
#     p.add_argument("file", nargs="?", help="Input file (default: stdin)")
#     args = p.parse_args()

#     fh = open(args.file, "r", encoding="utf-8", errors="replace") if args.file else sys.stdin

#     so_sum = defaultdict(float)
#     total = 0.0

#     for line in fh:
#         m = LINE_RE.match(line)
#         if not m:
#             continue

#         overhead = float(m.group(1))
#         shared_object = m.group(2)

#         so_sum[shared_object] += overhead
#         total += overhead

#     if fh is not sys.stdin:
#         fh.close()

#     print("Overhead%   Shared Object")
#     print("---------   ------------------------------")

#     for so, ov in sorted(so_sum.items(), key=lambda x: x[1], reverse=True):
#         print(f"{ov:8.2f}%   {so}")

#     print("---------")
#     print(f"Total sum: {total:.2f}%")

#     if abs(total - 100.0) < 0.5:
#         print("✔ Sum is approximately 100%")
#     else:
#         print("⚠ Sum is NOT 100% (input may be truncated or filtered)")

# if __name__ == "__main__":
#     main()