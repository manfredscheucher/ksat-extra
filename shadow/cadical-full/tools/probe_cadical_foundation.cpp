// Throwaway probe (golden values for FullFoundationTest.kt in the :cadical tests):
// checksums of libc++ std::sort with ties, CaDiCaL's rsort, Random, Reap and EMA.
//
//   c++ -std=c++11 -O1 -DNDEBUG -I<cadical>/src probe_cadical_foundation.cpp \
//       <cadical>/src/reap.cpp <cadical>/src/ema.cpp -o probe && ./probe
#include "internal.hpp"
#include <algorithm>
#include <cinttypes>
#include <cstdio>
#include <cstring>
#include <vector>

using namespace CaDiCaL;

static uint64_t mix (uint64_t h, uint64_t v) { return h * 1099511628211ul + v; }

struct key_less {
  const std::vector<int> *keys;
  bool operator() (int a, int b) const { return (*keys)[a] < (*keys)[b]; }
};

struct score_less {
  const std::vector<double> *stab;
  bool operator() (unsigned a, unsigned b) {
    double s = (*stab)[a], t = (*stab)[b];
    if (s < t)
      return true;
    if (s > t)
      return false;
    return a > b;
  }
};

struct rank64 {
  const std::vector<uint64_t> *ranks;
  typedef uint64_t Type;
  Type operator() (int a) const { return (*ranks)[a]; }
};

struct rank32 {
  const std::vector<uint64_t> *ranks;
  typedef unsigned Type;
  Type operator() (int a) const { return (unsigned) (*ranks)[a]; }
};

int main () {
  Random random (42);
  // std::sort with many ties.
  const int sizes[] = {0, 1, 2, 3, 4, 5, 6, 7, 23, 24, 25, 31, 32, 33, 100,
                       128, 129, 200, 1000, 5000};
  const int ranges[] = {1, 2, 3, 10, 1000000};
  uint64_t h = 0;
  for (int n : sizes)
    for (int k : ranges) {
      std::vector<int> keys (n), v (n);
      for (int i = 0; i < n; i++)
        keys[i] = random.pick_int (0, k - 1), v[i] = i;
      key_less less;
      less.keys = &keys;
      std::sort (v.begin (), v.end (), less);
      for (int x : v)
        h = mix (h, x);
    }
  printf ("sort %" PRIu64 "\n", h);

  // rsort with 64 and 32 bit ranks (stable, but exercise the byte rounds).
  h = 0;
  for (int n : sizes)
    for (int bits = 0; bits < 64; bits += 9) {
      std::vector<uint64_t> ranks (n);
      std::vector<int> v (n), w (n);
      for (int i = 0; i < n; i++) {
        uint64_t r = random.next ();
        ranks[i] = bits ? (r >> (64 - bits)) : 0;
        v[i] = w[i] = i;
      }
      rank64 r64;
      r64.ranks = &ranks;
      rsort (v.begin (), v.end (), r64);
      rank32 r32;
      r32.ranks = &ranks;
      rsort (w.begin (), w.end (), r32);
      for (int x : v)
        h = mix (h, x);
      for (int x : w)
        h = mix (h, x);
    }
  printf ("rsort %" PRIu64 "\n", h);

  // Random.
  h = 0;
  for (int i = 0; i < 1000; i++) {
    h = mix (h, (uint64_t) (int64_t) random.pick_int (-7, 1000 + i));
    h = mix (h, (uint64_t) (int64_t) random.pick_log (3, 100000 + i));
    double d = random.generate_double ();
    uint64_t bits;
    memcpy (&bits, &d, sizeof bits);
    h = mix (h, bits);
    h = mix (h, random.generate_bool ());
  }
  printf ("random %" PRIu64 "\n", h);

  // Reap.
  h = 0;
  Reap reap; // the solver never calls 'init' (shrink.cpp only pushes, pops, clears)
  for (int round = 0; round < 50; round++) {
    unsigned base = 0;
    for (int i = 0; i < 40; i++)
      reap.push (base + (random.generate () % 5000));
    while (!reap.empty ())
      h = mix (h, reap.pop ());
    reap.clear ();
  }
  printf ("reap %" PRIu64 "\n", h);

  // EMA.
  h = 0;
  EMA ema;
  INIT_EMA (ema, 33);
  for (int i = 0; i < 1000; i++) {
    ema.update (0, random.pick_int (0, 50), "ema");
    double d = ema;
    uint64_t bits;
    memcpy (&bits, &d, sizeof bits);
    h = mix (h, bits);
  }
  printf ("ema %" PRIu64 "\n", h);

  // Heap with the 'score_smaller' comparator (ties broken by index).
  h = 0;
  std::vector<double> stab (2001);
  score_less sl;
  sl.stab = &stab;
  heap<score_less> scores (sl);
  for (unsigned idx = 1; idx <= 2000; idx++) {
    stab[idx] = random.pick_int (0, 20);
    scores.push_back (idx);
  }
  for (int i = 0; i < 3000; i++) {
    unsigned idx = random.pick_int (1, 2000);
    if (!scores.contains (idx))
      continue;
    stab[idx] += random.pick_int (0, 3);
    scores.update (idx);
    if (i % 3 == 0)
      h = mix (h, scores.pop_front ());
  }
  while (!scores.empty ())
    h = mix (h, scores.pop_front ());
  printf ("heap %" PRIu64 "\n", h);
  return 0;
}
