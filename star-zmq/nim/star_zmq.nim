## A single-threaded external peer binding, not an alternate StarLang runtime.
## Deliberately local-only until the authenticated federation port is available.
import std/strutils

when compileOption("threads"):
  {.error: "This first peer binding requires --threads:off; never share ZMQ sockets.".}

const
  DefaultLibrary = when defined(windows): "libzmq.dll"
                   elif defined(macosx): "libzmq.dylib"
                   else: "libzmq.so.5"
  StarZmqLibrary {.strdefine.} = DefaultLibrary
  PayloadLimit* = 1_048_576

proc ctxNew(): pointer {.cdecl, importc: "zmq_ctx_new", dynlib: StarZmqLibrary.}
proc ctxTerm(ctx: pointer): cint {.cdecl, importc: "zmq_ctx_term", dynlib: StarZmqLibrary.}
proc socketNew(ctx: pointer; kind: cint): pointer {.cdecl, importc: "zmq_socket", dynlib: StarZmqLibrary.}
proc socketClose(socket: pointer): cint {.cdecl, importc: "zmq_close", dynlib: StarZmqLibrary.}
proc socketConnect(socket: pointer; endpoint: cstring): cint {.cdecl, importc: "zmq_connect", dynlib: StarZmqLibrary.}
proc setOpt(socket: pointer; option: cint; data: pointer; size: csize_t): cint {.cdecl, importc: "zmq_setsockopt", dynlib: StarZmqLibrary.}
proc getOpt(socket: pointer; option: cint; data: pointer; size: ptr csize_t): cint {.cdecl, importc: "zmq_getsockopt", dynlib: StarZmqLibrary.}
proc sendRaw(socket: pointer; data: pointer; size: csize_t; flags: cint): cint {.cdecl, importc: "zmq_send", dynlib: StarZmqLibrary.}
proc recvRaw(socket: pointer; data: pointer; size: csize_t; flags: cint): cint {.cdecl, importc: "zmq_recv", dynlib: StarZmqLibrary.}
proc errorNumber(): cint {.cdecl, importc: "zmq_errno", dynlib: StarZmqLibrary.}
proc errorString(code: cint): cstring {.cdecl, importc: "zmq_strerror", dynlib: StarZmqLibrary.}

type
  ZmqError* = object of CatchableError
    code*: int
  Dealer* = ref object
    context: pointer
    socket: pointer

var activeDealer: bool

proc checked(value: cint; operation: string): cint =
  if value < 0:
    let code = errorNumber()
    var failure = newException(ZmqError, operation & ": " & $errorString(code))
    failure.code = int(code)
    raise failure
  value

proc localEndpoint*(endpoint: string): bool =
  if endpoint.len == 0 or endpoint.len > 1024 or '\0' in endpoint:
    return false
  if endpoint.startsWith("ipc://") and endpoint.len > 6: return true
  # inproc is process-local and cannot connect this child to a Lisp parent.
  for prefix in ["tcp://127.0.0.1:", "tcp://[::1]:"]:
    if endpoint.startsWith(prefix):
      let port = endpoint[prefix.len .. ^1]
      if port.len < 1 or port.len > 5: return false
      for c in port:
        if c notin {'0'..'9'}: return false
      let number = parseInt(port)
      return number >= 1 and number <= 65535
  false

proc close*(dealer: Dealer) =
  if dealer.isNil: return
  if dealer.socket != nil:
    discard checked(socketClose(dealer.socket), "close")
    dealer.socket = nil
  if dealer.context != nil:
    discard checked(ctxTerm(dealer.context), "context-term")
    dealer.context = nil
    activeDealer = false

proc openDealer*(endpoint, identity: string; timeoutMs = 5000; lingerMs = 0): Dealer =
  if not localEndpoint(endpoint) or identity.len notin 1..255 or
      identity[0] == '\0' or timeoutMs notin 1..60000 or lingerMs notin 0..5000:
    raise newException(ValueError, "Invalid local endpoint, identity, timeout, or linger")
  if activeDealer:
    raise newException(ValueError, "One peer/context per process in this binding")
  new(result)
  result.context = ctxNew()
  if result.context == nil:
    discard checked(-1, "context-new")
  activeDealer = true
  try:
    result.socket = socketNew(result.context, 5) # DEALER
    if result.socket == nil: discard checked(-1, "socket")
    for entry in [(17.cint, cint(lingerMs)), (23.cint, 64.cint), (24.cint, 64.cint),
                  (27.cint, cint(timeoutMs)), (28.cint, cint(timeoutMs)), (39.cint, 1.cint)]:
      var value = entry[1]
      discard checked(setOpt(result.socket, entry[0], addr value, csize_t(sizeof(value))), "setsockopt")
    var maxBytes = int64(PayloadLimit)
    discard checked(setOpt(result.socket, 22, addr maxBytes, csize_t(sizeof(maxBytes))), "max-message-size")
    discard checked(setOpt(result.socket, 5, cast[pointer](identity.cstring), csize_t(identity.len)), "routing-id")
    discard checked(socketConnect(result.socket, endpoint.cstring), "connect")
  except:
    result.close()
    raise

proc requireOpen(dealer: Dealer) =
  if dealer.isNil or dealer.socket == nil:
    raise newException(ValueError, "Dealer is closed")

proc send*(dealer: Dealer; payload: string) =
  dealer.requireOpen()
  if payload.len > PayloadLimit:
    raise newException(ValueError, "Payload limit exceeded")
  let written = checked(sendRaw(dealer.socket, cast[pointer](payload.cstring), csize_t(payload.len), 0), "send")
  if written != payload.len:
    dealer.close()
    raise newException(ValueError, "Unexpected short send")

proc receive*(dealer: Dealer): string =
  dealer.requireOpen()
  result = newString(PayloadLimit)
  # No read past the allocated buffer: the returned native length can be larger.
  let size = checked(recvRaw(dealer.socket, addr result[0], csize_t(result.len), 0), "receive")
  try:
    if size > PayloadLimit:
      raise newException(ValueError, "Truncated/oversized payload")
    var more: cint
    var optionSize = csize_t(sizeof(more))
    discard checked(getOpt(dealer.socket, 13, addr more, addr optionSize), "receive-more")
    if more != 0:
      raise newException(ValueError, "Unexpected multipart payload")
    result.setLen(int(size))
  except:
    dealer.close()
    raise
