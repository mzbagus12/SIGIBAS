// SPDX-License-Identifier: GPL-3.0-only
// Local SHA-256 implementation (FIPS 180-4), no external dependency.
// Integrity only; hashes are not signatures/authentication.
int _power256(int n) {
  var value = 1;
  for (var i = 0; i < n; i++) {
    value *= 256;
  }
  return value;
}

String sha256(List<int> bytes) {
  const k = [
    0x428a2f98,
    0x71374491,
    0xb5c0fbcf,
    0xe9b5dba5,
    0x3956c25b,
    0x59f111f1,
    0x923f82a4,
    0xab1c5ed5,
    0xd807aa98,
    0x12835b01,
    0x243185be,
    0x550c7dc3,
    0x72be5d74,
    0x80deb1fe,
    0x9bdc06a7,
    0xc19bf174,
    0xe49b69c1,
    0xefbe4786,
    0x0fc19dc6,
    0x240ca1cc,
    0x2de92c6f,
    0x4a7484aa,
    0x5cb0a9dc,
    0x76f988da,
    0x983e5152,
    0xa831c66d,
    0xb00327c8,
    0xbf597fc7,
    0xc6e00bf3,
    0xd5a79147,
    0x06ca6351,
    0x14292967,
    0x27b70a85,
    0x2e1b2138,
    0x4d2c6dfc,
    0x53380d13,
    0x650a7354,
    0x766a0abb,
    0x81c2c92e,
    0x92722c85,
    0xa2bfe8a1,
    0xa81a664b,
    0xc24b8b70,
    0xc76c51a3,
    0xd192e819,
    0xd6990624,
    0xf40e3585,
    0x106aa070,
    0x19a4c116,
    0x1e376c08,
    0x2748774c,
    0x34b0bcb5,
    0x391c0cb3,
    0x4ed8aa4a,
    0x5b9cca4f,
    0x682e6ff3,
    0x748f82ee,
    0x78a5636f,
    0x84c87814,
    0x8cc70208,
    0x90befffa,
    0xa4506ceb,
    0xbef9a3f7,
    0xc67178f2,
  ];
  final h = [
    0x6a09e667,
    0xbb67ae85,
    0x3c6ef372,
    0xa54ff53a,
    0x510e527f,
    0x9b05688c,
    0x1f83d9ab,
    0x5be0cd19,
  ];
  final data = <int>[...bytes, 0x80];
  while (data.length % 64 != 56) {
    data.add(0);
  }
  final bits = bytes.length * 8;
  for (var i = 7; i >= 0; i--) {
    data.add((bits ~/ _power256(i)) & 255);
  }
  int rotr(int v, int n) => ((v >>> n) | (v << (32 - n))) & 0xffffffff;
  for (var offset = 0; offset < data.length; offset += 64) {
    final w = List<int>.filled(64, 0);
    for (var i = 0; i < 16; i++) {
      final j = offset + i * 4;
      w[i] =
          (data[j] << 24) |
          (data[j + 1] << 16) |
          (data[j + 2] << 8) |
          data[j + 3];
    }
    for (var i = 16; i < 64; i++) {
      final a = w[i - 15], b = w[i - 2];
      w[i] =
          (w[i - 16] +
              (rotr(a, 7) ^ rotr(a, 18) ^ (a >>> 3)) +
              w[i - 7] +
              (rotr(b, 17) ^ rotr(b, 19) ^ (b >>> 10))) &
          0xffffffff;
    }
    var a = h[0],
        b = h[1],
        c = h[2],
        d = h[3],
        e = h[4],
        f = h[5],
        g = h[6],
        v = h[7];
    for (var i = 0; i < 64; i++) {
      final t1 =
          (v +
              (rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)) +
              ((e & f) ^ ((~e) & g)) +
              k[i] +
              w[i]) &
          0xffffffff;
      final t2 =
          ((rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)) +
              ((a & b) ^ (a & c) ^ (b & c))) &
          0xffffffff;
      v = g;
      g = f;
      f = e;
      e = (d + t1) & 0xffffffff;
      d = c;
      c = b;
      b = a;
      a = (t1 + t2) & 0xffffffff;
    }
    final state = [a, b, c, d, e, f, g, v];
    for (var i = 0; i < 8; i++) {
      h[i] = (h[i] + state[i]) & 0xffffffff;
    }
  }
  return h.map((x) => x.toRadixString(16).padLeft(8, '0')).join();
}
