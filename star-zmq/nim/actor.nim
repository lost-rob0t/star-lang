## Local, persistent example actor. This is a lifecycle-envelope client, not
## a StarLang compiler/runtime, registry, journal, or federation authority.
import std/[json, os, sets, strutils, unicode]
import star_zmq

type Scan = object
  text: string
  offset, count: int

proc invalid() {.noreturn.} =
  raise newException(ValueError, "Invalid bounded lifecycle JSON")

proc peek(s: Scan): char =
  if s.offset < s.text.len: s.text[s.offset] else: '\0'

proc take(s: var Scan; c: char) =
  if s.peek != c: invalid()
  inc s.offset

proc whitespace(s: var Scan) =
  while s.peek in {' ', '\t', '\r', '\n'}: inc s.offset

proc quoted(s: var Scan): string =
  let start = s.offset
  s.take('"')
  while true:
    let c = s.peek
    if c < ' ': invalid()
    inc s.offset
    if c == '"': break
    if c == '\\':
      let escaped = s.peek
      if escaped notin {'"', '\\', '/', 'b', 'f', 'n', 'r', 't', 'u'}: invalid()
      inc s.offset
      if escaped == 'u':
        for unused in 0..<4:
          if s.peek notin {'0'..'9', 'a'..'f', 'A'..'F'}: invalid()
          inc s.offset
  result = parseJson(s.text[start..<s.offset]).getStr()
  if validateUtf8(result) != -1: invalid()

proc number(s: var Scan) =
  let start = s.offset
  if s.peek == '-': inc s.offset
  if s.peek == '0': inc s.offset
  else:
    if s.peek notin {'1'..'9'}: invalid()
    while s.peek in {'0'..'9'}: inc s.offset
  if s.peek == '.':
    inc s.offset
    if s.peek notin {'0'..'9'}: invalid()
    while s.peek in {'0'..'9'}: inc s.offset
  if s.peek in {'e', 'E'}:
    inc s.offset
    if s.peek in {'+', '-'}: inc s.offset
    if s.peek notin {'0'..'9'}: invalid()
    while s.peek in {'0'..'9'}: inc s.offset
  if s.offset - start > 128: invalid()

proc value(s: var Scan; depth: int) =
  inc s.count
  if depth > 32 or s.count > 16384: invalid()
  s.whitespace()
  case s.peek
  of '"': discard s.quoted()
  of '{':
    inc s.offset
    s.whitespace()
    var keys = initHashSet[string]()
    if s.peek != '}':
      while true:
        s.whitespace()
        let key = s.quoted()
        if key in keys: invalid()
        keys.incl(key)
        s.whitespace()
        s.take(':')
        s.value(depth + 1)
        s.whitespace()
        if s.peek != ',': break
        inc s.offset
    s.take('}')
  of '[':
    inc s.offset
    s.whitespace()
    if s.peek != ']':
      while true:
        s.value(depth + 1)
        s.whitespace()
        if s.peek != ',': break
        inc s.offset
    s.take(']')
  of 't':
    for c in "true": s.take(c)
  of 'f':
    for c in "false": s.take(c)
  of 'n':
    for c in "null": s.take(c)
  else: s.number()

proc decode(data: string): JsonNode =
  if data.len notin 1..PayloadLimit or validateUtf8(data) != -1: invalid()
  var scanner = Scan(text: data)
  scanner.value(0)
  scanner.whitespace()
  if scanner.offset != data.len: invalid()
  result = parseJson(data)
  if result.kind != JObject: invalid()

proc requiredText(node: JsonNode; key: string): string =
  if not node.hasKey(key) or node[key].kind != JString: invalid()
  result = node[key].getStr()
  if result.len == 0: invalid()

proc validateCommand(node: JsonNode; actor: string) =
  const fields = ["starVersion", "kind", "messageId", "messageType", "actor",
    "sender", "correlationId", "causationId", "attempt", "idempotencyKey",
    "dataset", "replyTo", "sentAt", "deadline", "payload"]
  for key, child in node:
    if key notin fields: invalid()
    if key notin ["starVersion", "attempt", "payload"] and child.kind != JString: invalid()
  if not node.hasKey("starVersion") or node["starVersion"].kind != JInt or
      node["starVersion"].getBiggestInt() != 1: invalid()
  if requiredText(node, "kind") != "command" or requiredText(node, "actor") != actor: invalid()
  for key in ["messageId", "messageType", "correlationId", "idempotencyKey", "replyTo"]:
    discard requiredText(node, key)
  if not node.hasKey("attempt") or node["attempt"].kind != JInt or
      node["attempt"].getBiggestInt() < 1: invalid()
  if not node.hasKey("payload") or node["payload"].kind != JObject: invalid()
  # Deadline enforcement is the runtime's authority. This example does not
  # pretend to support it: reject such requests rather than execute them late.
  if node.hasKey("deadline"): invalid()

proc response(source: JsonNode; actor, identity: string; sequence: int): JsonNode =
  result = %*{"starVersion": 1, "kind": "reply", "messageId": identity & ":" & $sequence,
    "messageType": source["messageType"].getStr(), "actor": source["replyTo"].getStr(),
    "sender": actor, "correlationId": source["correlationId"].getStr(),
    "causationId": source["messageId"].getStr(), "attempt": 1, "payload": {}}
  if source.hasKey("dataset"): result["dataset"] = source["dataset"]

proc run() =
  if paramCount() != 4:
    raise newException(ValueError, "Expected endpoint, identity, actor, generation")
  let endpoint = paramStr(1)
  let identity = paramStr(2)
  let actor = paramStr(3)
  let generation = parseInt(paramStr(4))
  if actor.len == 0 or generation < 0 or generation > 2147483647: invalid()
  # Bounded idle lifetime; no busy polling. A real supervisor owns restart policy.
  let dealer = openDealer(endpoint, identity, timeoutMs = 60000, lingerMs = 1000)
  try:
    dealer.send($(%*{"starVersion": 1, "kind": "event", "messageId": identity & ":ready",
      "messageType": "star.zmq/ready@1", "actor": actor, "sender": actor,
      "correlationId": identity & ":ready", "attempt": 1, "payload": {"generation": generation}}))
    # Bound the example's lifetime even under an endless stream of requests.
    for sequence in 1..100000:
      let command = decode(dealer.receive())
      validateCommand(command, actor)
      var reply = response(command, actor, identity, sequence)
      case command["messageType"].getStr()
      of "star.zmq/echo@1":
        if command["payload"].len != 1 or not command["payload"].hasKey("text") or
            command["payload"]["text"].kind != JString: invalid()
        reply["payload"] = command["payload"]
      of "star.zmq/stop@1":
        if command["payload"].len != 0: invalid()
        dealer.send($reply)
        return
      else:
        reply["kind"] = %"error"
        reply["messageType"] = %"star.protocol/error@1"
        reply["payload"] = %*{"forMessageId": command["messageId"].getStr(),
          "code": "unsupportedMessage", "message": "The example actor does not handle this message.",
          "retryable": false}
      dealer.send($reply)
  finally:
    dealer.close()

when isMainModule:
  try:
    run()
  except CatchableError:
    # No payload, argv, endpoint, or exception data in logs.
    stderr.writeLine("star-zmq example actor stopped with a protocol or transport error")
    quit(1)
