# SPDX-FileCopyrightText: 2021 ☭ Emery Hemingway
# SPDX-License-Identifier: Unlicense

# TODO: add a logging callback

import std/[asyncdispatch, asyncnet, parseutils, net, os, parseopt, strutils, uri]
import ./private/asynchttpserver
import tkrzw
import eris, eris_tkrzw/filedbs

type StoreServer* = ref object
  store: ErisStore
  http: AsyncHttpServer

using server: StoreServer

proc userAgent*(req: Request): string =
  $req.headers.getOrDefault("user-agent")

proc newStoreServer*(store: ErisStore): StoreServer =
  StoreServer(store: store, http: newAsyncHttpServer())

proc erisCap(req: Request): ErisCap =
  let elems = req.url.path.split '/'
  if elems.len != 2:
    raise newException(ValueError, "bad path " & req.url.path)
  parseErisUrn elems[1]

proc parseRange(range: string): tuple[a: BiggestInt, b: BiggestInt] =
  ## Parse an HTTP byte range string.
  if range != "":
    var start = skip(range, "bytes=")
    if start > 0:
      start.inc parseBiggestInt(range, result.a, start)
      if skipWhile(range, {'-'}, start) == 1:
        discard parseBiggestInt(range, result.b, start+1)

proc get(server; req: Request): Future[void] {.async.} =
  var
    cap = req.erisCap
    stream = newErisStream(server.store, cap)
    totalLength = int(await stream.length)
    (startPos, endPos) = req.headers.getOrDefault("range").parseRange
  if endPos == 0 or endPos > startPos:
      endPos = pred totalLength
  var
    remain = succ(endPos - startPos)
    buf = newSeq[byte](min(remain, cap.blockSize.int))
    headers = newHttpHeaders({
      "connection": "close",
      "content-length": $remain,
      "content-range": "bytes $1-$2/$3" % [ $startPos, $endPos, $totalLength ]
    })
  await req.respond(Http206, "", headers)
  stream.setPosition(startPos)
  var n = int min(buf.len, remain)
  if (remain > cap.blockSize.int) and ((startPos and cap.blockSize.int.pred) != 0):
    # shorten the first read to align the stream
    n.dec(startPos.int and cap.blockSize.int.pred)
  try:
    while remain > 0 and not req.client.isClosed:
      n = await stream.readBuffer(addr buf[0], n)
      if n > 0:
        await req.client.send(addr buf[0], n, {})
        remain.dec(n)
        n = int min(buf.len, remain)
      else:
        break
  except: discard
  close(req.client)
  close(stream)

proc head(server; req: Request): Future[void] {.async.} =
  ## Check that ERIS data is available.
  var
    cap = req.erisCap
    stream = newErisStream(server.store, cap)
    len = await stream.length()
    headers = newHttpHeaders({"Accept-Ranges": "bytes"})
  await req.respond(Http200, "", headers)

proc put(server; req: Request): Future[void] {.async.} =
  let blockSize =
    if req.body.len < 4095: bs1k # TODO: less arbitrary math
    else: bs32k
  var cap = await server.store.encode(blockSize, req.body)
  await req.respond(Http200, "", newHttpHeaders({"content-location": "/" & $cap}))

proc serve*(server: StoreServer; port: Port; allowedMethods: set[HttpMethod]): Future[void] =
  proc handleRequest(req: Request) {.async.} =
    try:
      if req.reqMethod in allowedMethods:
        case req.reqMethod
        of HttpGET: await server.get(req)
        of HttpHEAD: await server.head(req)
        of HttpPUT: await server.put(req)
        else: discard
      else: await req.respond(Http403, "method not allowed")
    except KeyError:
      await req.respond(Http404, getCurrentExceptionMsg())
    except ValueError:
      await req.respond(Http400, getCurrentExceptionMsg())
    except:
      if not req.client.isClosed:
        discard req.respond(Http500, getCurrentExceptionMsg())

  server.http.serve(port, handleRequest, address = "::", domain = AF_INET6)

proc close*(server: StoreServer) =
  close(server.http)

when isMainModule:
  const
    dbEnvVar = "eris_db_file"
    usageMsg = """
Usage: erishttpd [OPTION]…
GET and PUT data to an ERIS store over HTTP.

Command line arguments:

  --port:…  HTTP listen port

  --get     Enable downloads using GET requests
  --head    Enable queries using HEAD requests
  --put     Enable uploading using PUT requests

The location of the database file is configured by the "$1"
environment variable.

Files may be uploaded using cURL:
curl -i --upload-file <FILE> http://[::1]:<PORT>

"""  % [dbEnvVar ]

  proc usage() =
    quit usageMsg

  proc failParam(kind: CmdLineKind, key, val: TaintedString) =
    quit "unhandled parameter " & key & " " & val

  var
    httpPort: Port
    allowedMethods: set[HttpMethod]

  for kind, key, val in getopt():
    case kind
    of cmdLongOption:
      case key
      of "port":
        if key == "": usage()
        else: httpPort = Port parseInt(val)
      of "get":
        allowedMethods.incl HttpGET
      of "head":
        allowedMethods.incl HttpHEAD
      of "put":
        allowedMethods.incl HttpPUT
      of "help": usage()
      else: failParam(kind, key, val)
    of cmdShortOption:
      case key
      of "h": usage()
      else: failParam(kind, key, val)
    of cmdArgument:
      failParam(kind, key, val)
    of cmdEnd: discard

  if allowedMethods == {}:
    quit "No HTTP method configured, see --help"

  var
    erisDbFile = absolutePath getEnv(dbEnvVar, "eris.tkh")
    store = newDbmStore(erisDbFile, writeable, {})
  echo "Serving store ", erisDbFile, " on port ", $httpPort, "."
  try:
    var storeServer = newStoreServer(store)
    waitFor storeServer.serve(httpPort, allowedMethods)
  finally: close(store)
