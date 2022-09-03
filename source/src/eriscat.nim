# SPDX-FileCopyrightText: 2021 ☭ Emery Hemingway
# SPDX-License-Identifier: Unlicense

import std/os

var
  args = commandLineParams()
  filePaths: seq[string]
  avgLen: int

const usage = """
Usage: eriscat FILE [FILE …]

Concatenate files to a stream with padding between ERIS block boundaries.
If the average file size is less than 16KiB then the output stream is padded to
align to 1KiB blocks, otherwise 32KiB.

This utility is intending for joining files in formats that support
concatenation such as Ogg containers. The resulting stream can be mostly
deduplicated with the individual encodings of each file.
"""

if args == @[]:
  writeLine(stderr, usage)
  quit("no files specified")

for arg in args:
  if fileExists(arg):
    let size = getFileSize(arg)
    if size > 0:
      inc(avgLen, int size)
      filePaths.add(arg)
  else:
    quit("not a file " & arg)

if filePaths.len < 1:
  quit("no files specified")

var
  blkLen = (if avgLen div filePaths.len < (16 shl 10): 1 else: 32) shl 10
    # use small blocks if the average files size is less than 16KiB
  blk = alloc(blkLen) # leak like a pro

for i, path in filePaths:
  var f: File
  if not open(f, path): quit("failed to open " & path)
  while true:
    var n = readBuffer(f, blk, blkLen)
    if writeBuffer(stdout, blk, n) != n:
      quit("write error")
    if n != blkLen:
      if i < filePaths.high:
        let padLen = blkLen - n
        zeroMem(blk, padLen)
        cast[ptr byte](blk)[] = 0x80
        if writeBuffer(stdout, blk, padLen) != padLen:
          quit("write error")
      break
  close(f)

quit(QuitSuccess)
