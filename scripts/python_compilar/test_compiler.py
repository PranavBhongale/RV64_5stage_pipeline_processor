#!/usr/bin/env python3
"""
test_compiler.py  —  automated tests for c_compiler.py
Writes .c files, runs the compiler, checks output is valid assembly.
"""
import os, sys, subprocess, textwrap

TESTS = {
    "01_arith.c": textwrap.dedent("""\
        int main() {
            int a = 10;
            int b = 3;
            int c = a + b;
            int d = a - b;
            int e = a * b;
            int f = a / b;
            int g = a % b;
            return g;
        }
    """),

    "02_if_else.c": textwrap.dedent("""\
        int max(int a, int b) {
            if (a > b) return a;
            else return b;
        }
        int main() {
            return max(7, 3);
        }
    """),

    "03_while.c": textwrap.dedent("""\
        int sum(int n) {
            int s = 0;
            int i = 1;
            while (i <= n) {
                s = s + i;
                i = i + 1;
            }
            return s;
        }
        int main() {
            return sum(10);
        }
    """),

    "04_for.c": textwrap.dedent("""\
        int factorial(int n) {
            int result = 1;
            for (int i = 2; i <= n; i = i + 1) {
                result = result * i;
            }
            return result;
        }
        int main() {
            return factorial(6);
        }
    """),

    "05_recursion.c": textwrap.dedent("""\
        int fib(int n) {
            if (n <= 1) return n;
            return fib(n - 1) + fib(n - 2);
        }
        int main() {
            return fib(10);
        }
    """),

    "06_global_var.c": textwrap.dedent("""\
        int counter = 0;
        int increment() {
            counter = counter + 1;
            return counter;
        }
        int main() {
            increment();
            increment();
            increment();
            return counter;
        }
    """),

    "07_array.c": textwrap.dedent("""\
        int sum_array(int arr[], int n) {
            int s = 0;
            for (int i = 0; i < n; i = i + 1) {
                s = s + arr[i];
            }
            return s;
        }
        int main() {
            int a[5];
            a[0] = 1; a[1] = 2; a[2] = 3; a[3] = 4; a[4] = 5;
            return sum_array(a, 5);
        }
    """),

    "08_nested_if.c": textwrap.dedent("""\
        int classify(int n) {
            if (n < 0) {
                return -1;
            } else if (n == 0) {
                return 0;
            } else {
                return 1;
            }
        }
        int main() {
            int a = classify(-5);
            int b = classify(0);
            int c = classify(42);
            return c;
        }
    """),

    "09_do_while.c": textwrap.dedent("""\
        int digits(int n) {
            int count = 0;
            do {
                n = n / 10;
                count = count + 1;
            } while (n > 0);
            return count;
        }
        int main() {
            return digits(12345);
        }
    """),

    "10_break_continue.c": textwrap.dedent("""\
        int first_even(int start, int limit) {
            for (int i = start; i <= limit; i = i + 1) {
                if (i % 2 == 0) return i;
            }
            return -1;
        }
        int count_odds(int n) {
            int count = 0;
            for (int i = 1; i <= n; i = i + 1) {
                if (i % 2 == 0) continue;
                count = count + 1;
            }
            return count;
        }
        int main() {
            return count_odds(10);
        }
    """),

    "11_bitwise.c": textwrap.dedent("""\
        int popcount(int n) {
            int count = 0;
            while (n != 0) {
                count = count + (n & 1);
                n = n >> 1;
            }
            return count;
        }
        int main() {
            return popcount(255);
        }
    """),

    "12_multi_func.c": textwrap.dedent("""\
        int square(int x) { return x * x; }
        int cube(int x)   { return x * square(x); }
        int power4(int x) { return square(square(x)); }
        int main() {
            int a = square(3);
            int b = cube(3);
            int c = power4(2);
            return a + b + c;
        }
    """),

    "13_logical.c": textwrap.dedent("""\
        int is_leap(int y) {
            return (y % 4 == 0 && y % 100 != 0) || (y % 400 == 0);
        }
        int main() {
            int a = is_leap(2000);
            int b = is_leap(1900);
            int c = is_leap(2024);
            return a + b + c;
        }
    """),

    "14_unary.c": textwrap.dedent("""\
        int abs_val(int n) {
            if (n < 0) return -n;
            return n;
        }
        int neg(int n) { return -n; }
        int main() {
            int a = abs_val(-42);
            int b = neg(5);
            return a + b;
        }
    """),

    "15_compound_assign.c": textwrap.dedent("""\
        int main() {
            int x = 10;
            x += 5;
            x -= 3;
            x *= 2;
            x /= 3;
            return x;
        }
    """),

    "16_global_array.c": textwrap.dedent("""\
        int primes[5];
        int main() {
            primes[0] = 2;
            primes[1] = 3;
            primes[2] = 5;
            primes[3] = 7;
            primes[4] = 11;
            int s = 0;
            for (int i = 0; i < 5; i = i + 1) {
                s = s + primes[i];
            }
            return s;
        }
    """),

    "17_nested_calls.c": textwrap.dedent("""\
        int add(int a, int b) { return a + b; }
        int mul(int a, int b) { return a * b; }
        int fma(int a, int b, int c) { return add(mul(a, b), c); }
        int main() {
            return fma(3, 4, 5);
        }
    """),

    "18_ternary.c": textwrap.dedent("""\
        int min(int a, int b) { return a < b ? a : b; }
        int clamp(int v, int lo, int hi) {
            return v < lo ? lo : (v > hi ? hi : v);
        }
        int main() {
            return clamp(15, 0, 10);
        }
    """),

    "19_gcd.c": textwrap.dedent("""\
        int gcd(int a, int b) {
            while (b != 0) {
                int t = b;
                b = a % b;
                a = t;
            }
            return a;
        }
        int lcm(int a, int b) {
            return a / gcd(a, b) * b;
        }
        int main() {
            return gcd(48, 18);
        }
    """),

    "20_hanoi.c": textwrap.dedent("""\
        int moves = 0;
        void hanoi(int n, int from, int to, int via) {
            if (n == 0) return;
            hanoi(n - 1, from, via, to);
            moves = moves + 1;
            hanoi(n - 1, via, to, from);
        }
        int main() {
            hanoi(4, 1, 3, 2);
            return moves;
        }
    """),
}


def run_test(name: str, code: str, out_dir: str) -> bool:
    c_path   = os.path.join(out_dir, name)
    asm_path = c_path.replace(".c", ".asm")

    with open(c_path, "w") as f:
        f.write(code)

    result = subprocess.run(
        [sys.executable, "c_compiler.py", c_path, "-o", asm_path],
        capture_output=True, text=True
    )

    if result.returncode != 0:
        print(f"  FAIL  {name}")
        print(f"        {result.stderr.strip()}")
        return False

    # Basic sanity: check output file has expected sections
    with open(asm_path) as f:
        asm = f.read()

    checks = [
        (".text"    in asm,                "missing .text section"),
        ("main:"    in asm or "main" in asm,"missing main label"),
        ("ADDI     sp, sp," in asm,        "missing stack frame"),
        ("JALR     zero, ra" in asm,       "missing return instruction"),
    ]
    for ok, msg in checks:
        if not ok:
            print(f"  FAIL  {name}  ({msg})")
            return False

    print(f"  PASS  {name}")
    return True


def main():
    os.chdir(os.path.dirname(os.path.abspath(__file__)))
    out_dir = "test_out"
    os.makedirs(out_dir, exist_ok=True)

    passed = failed = 0
    print("=" * 55)
    print("  RV64IM Compiler Test Suite")
    print("=" * 55)
    for name, code in sorted(TESTS.items()):
        if run_test(name, code, out_dir):
            passed += 1
        else:
            failed += 1

    print("=" * 55)
    print(f"  Results: {passed} passed, {failed} failed")
    print("=" * 55)
    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()
