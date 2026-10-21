// Throwaway probe: prints upstream CaDiCaL struct sizes needed by the Kotlin full port.
#include "internal.hpp"
#include <cstdio>
int main () {
  printf ("sizeof(Clause)=%zu bytes(2)=%zu bytes(3)=%zu\n", sizeof (CaDiCaL::Clause),
          CaDiCaL::Clause::bytes (2), CaDiCaL::Clause::bytes (3));
  return 0;
}
