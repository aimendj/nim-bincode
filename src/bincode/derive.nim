# SPDX-License-Identifier: Apache-2.0 OR MIT
# Copyright (c) Status Research & Development GmbH

{.push raises: [], gcsafe.}

import std/macros
import faststreams
import ./config
import ./codecs

## Generic macro derivation for Rust bincode-compatible serialization.
## Generates ``encode``, ``decode``, and ``decodeAt`` procedures for structs, enums,
## variants, and custom types.

func fieldIdent(name: NimNode): NimNode =
  var n = name
  if n.kind == nnkPostfix:
    n = n[1]
  if n.kind == nnkPragmaExpr:
    n = n[0]
  n

func getTypeDefBody(typeImpl: NimNode): NimNode =
  if typeImpl.kind != nnkTypeDef:
    error("deriveBincode expects a type definition, got " & $typeImpl.kind)
  var body = typeImpl[2]
  if body.kind == nnkRefTy:
    body = body[0]
  body

func collectFields(node: NimNode): seq[NimNode] =
  result = @[]
  if node.isNil:
    return
  case node.kind
  of nnkIdentDefs:
    for i in 0 ..< node.len - 2:
      result.add fieldIdent(node[i])
  of nnkRecCase:
    discard
  of nnkOfBranch, nnkElse:
    if node.len > 0:
      result.add collectFields(node[^1])
  else:
    for child in node:
      result.add collectFields(child)

func findRecCase(node: NimNode): NimNode =
  if node.kind == nnkRecCase:
    return node
  for child in node:
    let res = findRecCase(child)
    if res != nil:
      return res
  nil

func genEncodeProc(typeName, body: NimNode): NimNode =
  newProc(
    name = newTree(nnkPostfix, ident"*", ident"encode"),
    params = [
      newEmptyNode(),
      newIdentDefs(ident"stream", ident"OutputStreamHandle"),
      newIdentDefs(ident"value", typeName),
      newIdentDefs(ident"config", ident"BincodeConfig", newCall(ident"standard")),
    ],
    body = body,
    pragmas = newTree(
      nnkPragma,
      newTree(
        nnkExprColonExpr,
        ident"raises",
        newTree(nnkBracket, ident"BincodeError", ident"IOError"),
      ),
    ),
  )

func genDecodeAtProc(typeName, body: NimNode): NimNode =
  newProc(
    name = newTree(nnkPostfix, ident"*", ident"decodeAt"),
    params = [
      newTree(nnkPar, typeName, ident"int"),
      newIdentDefs(ident"data", newTree(nnkBracketExpr, ident"openArray", ident"byte")),
      newIdentDefs(ident"tParam", newTree(nnkBracketExpr, ident"typedesc", typeName)),
      newIdentDefs(ident"config", ident"BincodeConfig", newCall(ident"standard")),
      newIdentDefs(ident"start", ident"int", newLit(0)),
    ],
    body = body,
    procType = nnkFuncDef,
    pragmas = newTree(
      nnkPragma,
      newTree(nnkExprColonExpr, ident"raises", newTree(nnkBracket, ident"BincodeError")),
    ),
  )

func genWrapperProcs(typeName: NimNode): NimNode =
  result = quote:
    proc decode*(
        data: openArray[byte],
        tParam: typedesc[`typeName`],
        config: BincodeConfig = standard(),
    ): `typeName` {.raises: [BincodeError].} =
      let (res, n) = decodeAt(data, tParam, config, 0)
      checkNoTrailingBytes(data.len, 0, n)
      res

    proc decode*(
        data: openArray[byte], value: var `typeName`, config: BincodeConfig = standard()
    ) {.raises: [BincodeError].} =
      value = decode(data, typedesc[`typeName`], config)

    proc encode*(
        value: `typeName`, config: BincodeConfig = standard()
    ): seq[byte] {.raises: [BincodeError].} =
      var stream = memoryOutput()
      try:
        encode(stream, value, config)
      except IOError as exc:
        raise newException(BincodeError, exc.msg)
      stream.getOutput()

func genFieldEncoders(fields: seq[NimNode]): NimNode =
  result = newStmtList()
  for f in fields:
    result.add newCall(
      ident"encode", ident"stream", newDotExpr(ident"value", f), ident"config"
    )

func genFieldDecoders(fields: seq[NimNode]): NimNode =
  result = newStmtList()
  for f in fields:
    let vSym = genSym(nskLet, "v")
    let nSym = genSym(nskLet, "n")
    result.add newTree(
      nnkLetSection,
      newTree(
        nnkVarTuple,
        vSym,
        nSym,
        newEmptyNode(),
        newCall(
          ident"decodeAt",
          ident"data",
          newCall(ident"typeof", newDotExpr(ident"res", f)),
          ident"config",
          ident"cur",
        ),
      ),
    )
    result.add newAssignment(newDotExpr(ident"res", f), vSym)
    result.add newAssignment(ident"cur", newCall(ident"+", ident"cur", nSym))

macro deriveBincode*(typ: typed, lengthPrefixed: static[bool] = false): untyped =
  ## Automatically derive Rust bincode serializers and deserializers for ``typ``.
  let typeSym = typ
  let typeName = ident($typeSym)
  let impl = typeSym.getImpl()
  let body = getTypeDefBody(impl)

  result = newStmtList()

  if body.kind == nnkEnumTy:
    # Enum serialization: encoded as 32-bit unsigned integer discriminant
    let serBody = newCall(
      ident"encodeBincodeEnumDiscriminant",
      ident"stream",
      newCall(ident"ord", ident"value"),
      ident"config",
    )

    var caseStmt = newTree(nnkCaseStmt, ident"disc")
    for item in body:
      let enumIdent =
        case item.kind
        of nnkIdent, nnkSym:
          item
        of nnkEnumFieldDef:
          item[0]
        of nnkEmpty:
          continue
        else:
          continue
      caseStmt.add newTree(
        nnkOfBranch,
        newTree(nnkDotExpr, newCall(ident"ord", enumIdent), ident"uint32"),
        newTree(nnkReturnStmt, newTree(nnkPar, enumIdent, ident"used")),
      )
    caseStmt.add newTree(
      nnkElse,
      newTree(
        nnkRaiseStmt,
        newCall(
          ident"newException",
          ident"BincodeError",
          newTree(
            nnkInfix,
            ident"&",
            newLit("Invalid enum discriminant for " & $typeName & ": "),
            newTree(nnkPrefix, ident"$", ident"disc"),
          ),
        ),
      ),
    )

    let deserAtBody = newStmtList(
      newTree(
        nnkLetSection,
        newTree(
          nnkVarTuple,
          ident"disc",
          ident"used",
          newEmptyNode(),
          newCall(
            ident"decodeBincodeEnumDiscriminant",
            ident"data",
            ident"config",
            ident"start",
          ),
        ),
      ),
      caseStmt,
    )

    result.add genEncodeProc(typeName, serBody)
    result.add genDecodeAtProc(typeName, deserAtBody)
    result.add genWrapperProcs(typeName)
    return result

  let recCaseNode = findRecCase(body)

  if recCaseNode != nil:
    # Variant / Case Object serialization
    let discDef = recCaseNode[0]
    let discField = fieldIdent(discDef[0])

    var serCase = newTree(nnkCaseStmt, newDotExpr(ident"value", discField))
    var deserCase = newTree(nnkCaseStmt, ident"disc")

    for i in 1 ..< recCaseNode.len:
      let branch = recCaseNode[i]
      if branch.kind in {nnkOfBranch, nnkElse}:
        let branchFields = collectFields(branch)
        let serBranchStmts = genFieldEncoders(branchFields)
        let deserBranchStmts = genFieldDecoders(branchFields)

        if branch.kind == nnkOfBranch:
          var ofSer = newTree(nnkOfBranch)
          var ofDeser = newTree(nnkOfBranch)
          for j in 0 ..< branch.len - 1:
            ofSer.add branch[j].copyNimTree()
            ofDeser.add branch[j].copyNimTree()
          ofSer.add serBranchStmts
          ofDeser.add deserBranchStmts
          serCase.add ofSer
          deserCase.add ofDeser
        else:
          serCase.add newTree(nnkElse, serBranchStmts)
          deserCase.add newTree(nnkElse, deserBranchStmts)

    let serBody = newStmtList(
      newCall(
        ident"encode", ident"stream", newDotExpr(ident"value", discField), ident"config"
      ),
      serCase,
    )

    let deserAtBody = newStmtList(
      newVarStmt(ident"cur", ident"start"),
      newTree(
        nnkLetSection,
        newTree(
          nnkVarTuple,
          ident"disc",
          ident"discUsed",
          newEmptyNode(),
          newCall(
            ident"decodeAt",
            ident"data",
            newTree(nnkBracketExpr, ident"typedesc", discDef[1]),
            ident"config",
            ident"cur",
          ),
        ),
      ),
      newAssignment(ident"cur", newCall(ident"+", ident"cur", ident"discUsed")),
      newTree(
        nnkVarSection,
        newIdentDefs(
          ident"res",
          typeName,
          newTree(
            nnkObjConstr, typeName, newTree(nnkExprColonExpr, discField, ident"disc")
          ),
        ),
      ),
      deserCase,
      newTree(
        nnkReturnStmt,
        newTree(nnkPar, ident"res", newCall(ident"-", ident"cur", ident"start")),
      ),
    )

    result.add genEncodeProc(typeName, serBody)
    result.add genDecodeAtProc(typeName, deserAtBody)
    result.add genWrapperProcs(typeName)
    return result

  # Standard Object / Struct serialization
  let fields = collectFields(body)
  let serStmts = genFieldEncoders(fields)
  let deserStmts = genFieldDecoders(fields)

  if lengthPrefixed:
    let serBody = newStmtList(
      newVarStmt(ident"subMem", newCall(ident"memoryOutput")),
      newBlockStmt(
        newEmptyNode(), newStmtList(newLetStmt(ident"stream", ident"subMem"), serStmts)
      ),
      newLetStmt(ident"rawBytes", newCall(ident"getOutput", ident"subMem")),
      newCall(
        ident"encodePrefixedByteSeq", ident"stream", ident"rawBytes", ident"config"
      ),
    )

    let deserAtBody = newStmtList(
      newTree(
        nnkLetSection,
        newTree(
          nnkVarTuple,
          ident"payload",
          ident"used",
          newEmptyNode(),
          newCall(
            ident"decodePrefixedByteSeq", ident"data", ident"config", ident"start"
          ),
        ),
      ),
      newVarStmt(ident"cur", newLit(0)),
      newTree(nnkVarSection, newIdentDefs(ident"res", typeName, newEmptyNode())),
      newBlockStmt(
        newEmptyNode(), newStmtList(newLetStmt(ident"data", ident"payload"), deserStmts)
      ),
      newTree(nnkReturnStmt, newTree(nnkPar, ident"res", ident"used")),
    )

    result.add genEncodeProc(typeName, serBody)
    result.add genDecodeAtProc(typeName, deserAtBody)
  else:
    let serBody = serStmts
    let deserAtBody = newStmtList(
      newVarStmt(ident"cur", ident"start"),
      newTree(nnkVarSection, newIdentDefs(ident"res", typeName, newEmptyNode())),
      deserStmts,
      newTree(
        nnkReturnStmt,
        newTree(nnkPar, ident"res", newCall(ident"-", ident"cur", ident"start")),
      ),
    )

    result.add genEncodeProc(typeName, serBody)
    result.add genDecodeAtProc(typeName, deserAtBody)

  result.add genWrapperProcs(typeName)

macro deriveBincodeCustom*(
    typ: typed,
    encodeProc: typed,
    decodeProc: typed,
    decodeErrorType: typed = CatchableError,
): untyped =
  ## Generate ``encode`` / ``decode`` / ``decodeAt`` procs for a custom type
  ## using custom ``encodeProc(val)`` and ``decodeProc(bytes)``.
  let typeName = ident($typ)

  let serBody = newCall(
    ident"encode", ident"stream", newCall(encodeProc, ident"value"), ident"config"
  )

  let deserAtBody = newStmtList(
    newTree(
      nnkLetSection,
      newTree(
        nnkVarTuple,
        ident"payload",
        ident"nbytes",
        newEmptyNode(),
        newCall(ident"decodePrefixedByteSeq", ident"data", ident"config", ident"start"),
      ),
    ),
    newTree(
      nnkTryStmt,
      newTree(
        nnkReturnStmt,
        newTree(nnkPar, newCall(decodeProc, ident"payload"), ident"nbytes"),
      ),
      newTree(
        nnkExceptBranch,
        newTree(nnkInfix, ident"as", decodeErrorType, ident"e"),
        newTree(
          nnkRaiseStmt,
          newCall(
            ident"newException", ident"BincodeError", newDotExpr(ident"e", ident"msg")
          ),
        ),
      ),
    ),
  )

  result = newStmtList()
  result.add genEncodeProc(typeName, serBody)
  result.add genDecodeAtProc(typeName, deserAtBody)
  result.add genWrapperProcs(typeName)

{.pop.}
