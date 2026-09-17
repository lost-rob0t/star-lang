## One-shot byte echo for CL/Nim interoperability; NOT a federation actor.
import std/os
import star_zmq

if paramCount() != 2:
  stderr.writeLine("usage: star-zmq-peer LOCAL_ENDPOINT ROUTING_ID")
  quit(2)

try:
  let dealer = openDealer(paramStr(1), paramStr(2))
  try:
    dealer.send("ready")
    let payload = dealer.receive()
    dealer.send(payload)
    # LINGER=0 is intentional. Wait for a receipt so close cannot discard echo.
    if dealer.receive() != "done":
      raise newException(ValueError, "Missing transport receipt")
  finally:
    dealer.close()
except CatchableError as error:
  stderr.writeLine(error.msg)
  quit(1)
