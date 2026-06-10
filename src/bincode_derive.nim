# SPDX-License-Identifier: Apache-2.0 OR MIT
# Copyright (c) Status Research & Development GmbH

{.push raises: [], gcsafe.}

import std/[macros, tables]
from stew/shims/macros import FieldDescription, recordFields
import faststreams

## ``deriveBincode MyType`` generates ``serializeMyType``, ``deserializeMyType``,
## ``deserializeMyTypeAt``, and ``serializeMyTypeToSeq``.

type
  FieldKind* = enum
    fkBool
    fkString
    fkChar
    fkScalar
    fkSeqByte
    fkSeq
    fkArray
    fkEnum
    fkObject
    fkBytesNewtype

  TypeInfo* = object
    kind*: FieldKind
    scalarSuffix*: string
    elemType*: NimNode
    arrayLen*: NimNode
    typeSym*: NimNode

func skipTypeModifiers(t: NimNode): NimNode =
  result = t
  while result.kind == nnkBracketExpr and result[0].kind == nnkIdent and
      $result[0] in ["sink", "lent", "owned"]:
    result = result[1]

func typeSymName(t: NimNode): string =
  let t = skipTypeModifiers(t)
  if t.kind == nnkSym:
    $t
  elif t.kind == nnkIdent:
    $t
  else:
    t.repr

func isEnumType(sym: NimNode): bool =
  if sym.kind != nnkSym:
    return false
  let impl = sym.getImpl()
  impl.expectKind nnkTypeDef
  impl[2].kind == nnkEnumTy

func resolveConcreteSym(sym: NimNode): NimNode =
  ## Follow ``type A = B`` chains until ``B`` is not a bare ``nnkSym`` alias body.
  result = sym
  if sym.kind != nnkSym:
    return
  var cur = sym
  for _ in 0 ..< 64:
    let impl = cur.getImpl()
    if impl.kind != nnkTypeDef:
      break
    let body = impl[2]
    if body.kind == nnkSym:
      cur = body
      result = cur
      continue
    break

func isObjectType(sym: NimNode): bool =
  if sym.kind != nnkSym:
    return false
  let impl = sym.getImpl()
  impl.expectKind nnkTypeDef
  impl[2].kind in {nnkObjectTy, nnkRefTy}

func arrayAliasBody(sym: NimNode): NimNode =
  if sym.kind != nnkSym:
    return nil
  let impl = sym.getImpl()
  if impl.kind != nnkTypeDef:
    return nil
  let body = impl[2]
  if body.kind != nnkBracketExpr:
    return nil
  let head =
    if body[0].kind == nnkSym:
      $body[0]
    elif body[0].kind == nnkIdent:
      $body[0]
    else:
      ""
  if head != "array":
    return nil
  body

func fieldIdent(name: NimNode): NimNode =
  ## ``name`` from `recordFields`_ (strips ``*`` / pragma wrappers).
  var n = name
  if n.kind == nnkPostfix:
    n = n[1]
  if n.kind == nnkPragmaExpr:
    n = n[0]
  n

func objectTypeBodyFromImpl(impl: NimNode): NimNode =
  var body = impl[2]
  if body.kind == nnkRefTy:
    body = body[0]
  return body

## Field definitions from an object type AST (under nnkRecList).
func iterObjectFieldDefs(body: NimNode): seq[NimNode] =
  result = @[]
  if body.kind != nnkObjectTy:
    return
  for part in body:
    if part.kind == nnkRecList:
      for f in part:
        if f.kind == nnkIdentDefs:
          result.add f
    elif part.kind == nnkIdentDefs:
      result.add part
    elif part.kind == nnkRecCase:
      return @[]

func newtypeDataArrayBracket(sym: NimNode): NimNode =
  ## ``array[len, byte]`` AST from the sole ``data`` field of a bytes newtype ``sym``.
  let rsym = resolveConcreteSym(sym)
  let impl = rsym.getImpl()
  let body = objectTypeBodyFromImpl(impl)
  let fields = iterObjectFieldDefs(body)
  if fields.len != 1:
    error("deriveBincode: bytes newtype must have one field: " & $sym & " (resolved: " &
        $rsym & ")")
  result = skipTypeModifiers(fields[0][1])

func tryByteArrayWrapper(sym: NimNode): TypeInfo =
  ## Libp2p-style ``object`` with only ``data*: array[N, byte]`` → ``N`` raw bytes.
  result = default(TypeInfo)
  let rsym = resolveConcreteSym(sym)
  if rsym.kind != nnkSym:
    return
  let impl = rsym.getImpl()
  if impl.kind != nnkTypeDef:
    return
  let body = objectTypeBodyFromImpl(impl)
  if body.kind != nnkObjectTy:
    return
  var names: seq[string] = @[]
  var typs: seq[NimNode] = @[]
  for f in iterObjectFieldDefs(body):
    names.add $fieldIdent(f[0])
    typs.add f[1]
  if names.len != 1 or names[0] != "data":
    return
  let ft = skipTypeModifiers(typs[0])
  if ft.kind != nnkBracketExpr or ft[0].kind notin {nnkIdent, nnkSym}:
    return
  let head = if ft[0].kind == nnkSym: $ft[0] else: $ft[0]
  if head != "array":
    return
  let elem = skipTypeModifiers(ft[2])
  if elem.kind != nnkIdent and elem.kind != nnkSym:
    return
  if $elem != "byte":
    return
  return TypeInfo(kind: fkBytesNewtype)

func classifyType(typ: NimNode): TypeInfo =
  let t = skipTypeModifiers(typ)
  if t.kind == nnkBracketExpr and t[0].kind in {nnkIdent, nnkSym}:
    let head = if t[0].kind == nnkSym: $t[0] else: $t[0]
    if head == "seq":
      let elem = t[1]
      if typeSymName(elem) == "byte":
        return TypeInfo(kind: fkSeqByte)
      return TypeInfo(kind: fkSeq, elemType: elem)
    if head == "array":
      return TypeInfo(kind: fkArray, arrayLen: t[1], elemType: t[2])
  let name = typeSymName(t)
  case name
  of "bool":
    TypeInfo(kind: fkBool)
  of "string":
    TypeInfo(kind: fkString)
  of "char":
    TypeInfo(kind: fkChar)
  of "byte":
    TypeInfo(kind: fkScalar, scalarSuffix: "U8")
  of "uint8":
    TypeInfo(kind: fkScalar, scalarSuffix: "U8")
  of "int8":
    TypeInfo(kind: fkScalar, scalarSuffix: "I8")
  of "uint16":
    TypeInfo(kind: fkScalar, scalarSuffix: "U16")
  of "int16":
    TypeInfo(kind: fkScalar, scalarSuffix: "I16")
  of "uint32":
    TypeInfo(kind: fkScalar, scalarSuffix: "U32")
  of "int32":
    TypeInfo(kind: fkScalar, scalarSuffix: "I32")
  of "uint64":
    TypeInfo(kind: fkScalar, scalarSuffix: "U64")
  of "int64":
    TypeInfo(kind: fkScalar, scalarSuffix: "I64")
  of "uint":
    TypeInfo(kind: fkScalar, scalarSuffix: "U64")
  of "int":
    TypeInfo(kind: fkScalar, scalarSuffix: "I64")
  of "float32":
    TypeInfo(kind: fkScalar, scalarSuffix: "F32")
  of "float64":
    TypeInfo(kind: fkScalar, scalarSuffix: "F64")
  else:
    if t.kind == nnkSym:
      let impl = t.getImpl()
      if impl.kind == nnkTypeDef and impl[2].kind notin {nnkObjectTy, nnkEnumTy, nnkRefTy}:
        return classifyType(impl[2])
      let ab = arrayAliasBody(t)
      if ab != nil:
        return TypeInfo(kind: fkArray, arrayLen: ab[1], elemType: ab[2])
      if isEnumType(t):
        return TypeInfo(kind: fkEnum, typeSym: t)
      ## Bytes newtypes (``data: array[N, byte]``) and other objects call
      ## ``serializeB`` so each type's ``deriveBincode`` options apply when nested.
      return TypeInfo(kind: fkObject, typeSym: t)
    else:
      error("deriveBincode: unsupported field type: " & name)

func bindIdent(name: string): NimNode =
  ## Non-hygienic identifier for AST spliced into generated procs.
  newIdentNode(name)

func caseFieldIdent(caseField: NimNode): NimNode =
  ## Discriminator field from a ``case`` object (``nnkRecCase`` header).
  if caseField.kind == nnkIdentDefs:
    fieldIdent(caseField[0])
  else:
    fieldIdent(caseField)

func objectTypeBody(typeImpl: NimNode): NimNode =
  var body = typeImpl[2]
  if body.kind == nnkRefTy:
    body = body[0]
  body

func collectRecCaseBranches(objectBody: NimNode): seq[NimNode] =
  result = @[]
  if objectBody.kind != nnkObjectTy:
    return
  for entry in objectBody[2]:
    if entry.kind == nnkRecCase:
      for i in 1 ..< entry.len:
        let branch = entry[i]
        if branch.kind == nnkOfBranch:
          result.add branch

func bincodeSerializeName(typeSym: NimNode): NimNode =
  ident("serialize" & $typeSym)

func bincodeDeserializeAtName(typeSym: NimNode): NimNode =
  ident("deserialize" & $typeSym & "At")

func bincodeDeserializeName(typeSym: NimNode): NimNode =
  ident("deserialize" & $typeSym)

func bincodeSerializeToSeqName(typeSym: NimNode): NimNode =
  ident("serialize" & $typeSym & "ToSeq")

func isByteElemType(elem: NimNode): bool =
  typeSymName(skipTypeModifiers(elem)) == "byte"

func buildSerializeAccess(
    info: TypeInfo, access, streamSym, configSym: NimNode,
    fieldTyp: NimNode = nil, lengthPrefixed: bool = false,
): NimNode =
  case info.kind
  of fkBool:
    newCall(ident"serializeBincodeBool", streamSym, access, configSym)
  of fkString:
    newCall(ident"serializeString", streamSym, access, configSym)
  of fkChar:
    newCall(ident"serializeBincodeChar", streamSym, access, configSym)
  of fkScalar:
    if info.scalarSuffix == "U32":
      newCall(ident"serializeBincodeU32", streamSym, access, configSym)
    else:
      newCall(
        ident("serializeBincode" & info.scalarSuffix), streamSym, access, configSym
      )
  of fkSeqByte:
    newCall(ident"serialize", streamSym, access, configSym)
  of fkSeq:
    let elemInfo = classifyType(info.elemType)
    let itemSym = bindIdent("item")
    let elemSer = buildSerializeAccess(
      elemInfo, itemSym, streamSym, configSym, info.elemType, lengthPrefixed
    )
    let lenExpr = newTree(
      nnkDotExpr, newDotExpr(access, bindIdent("len")), bindIdent("uint64")
    )
    return newStmtList(
      newCall(ident"encodeLength", streamSym, lenExpr, configSym),
      newTree(nnkForStmt, itemSym, access, newStmtList(elemSer)),
    )
  of fkArray:
    if lengthPrefixed and isByteElemType(info.elemType):
      return newCall(ident"serialize", streamSym, access, configSym)
    let elemInfo = classifyType(info.elemType)
    let iSym = bindIdent("i")
    let elemAccess = newTree(nnkBracketExpr, access, iSym)
    let elemSer = buildSerializeAccess(
      elemInfo, elemAccess, streamSym, configSym, info.elemType, lengthPrefixed
    )
    return newTree(
      nnkForStmt,
      iSym,
      newCall(ident"..<", newLit(0), info.arrayLen),
      newStmtList(elemSer),
    )
  of fkEnum:
    newCall(
      ident"serializeBincodeEnumDiscriminant",
      streamSym,
      newCall(ident"int", newCall(ident"ord", access)),
      configSym,
    )
  of fkBytesNewtype:
    let dataAcc = newTree(nnkDotExpr, access, bindIdent("data"))
    if lengthPrefixed:
      return newCall(ident"serialize", streamSym, dataAcc, configSym)
    let ft = newtypeDataArrayBracket(fieldTyp)
    let arrInfo = TypeInfo(
      kind: fkArray, arrayLen: ft[1], elemType: newIdentNode("by" & "te")
    )
    buildSerializeAccess(
      arrInfo, dataAcc, streamSym, configSym, lengthPrefixed = lengthPrefixed
    )
  of fkObject:
    newCall(bincodeSerializeName(info.typeSym), streamSym, access, configSym)

func decodeProcFor(info: TypeInfo): NimNode =
  case info.kind
  of fkBool:
    ident"deserializeBincodeBool"
  of fkString:
    ident"decodePrefixedString"
  of fkChar:
    ident"deserializeBincodeChar"
  of fkSeqByte:
    ident"decodePrefixedByteSeq"
  of fkScalar:
    if info.scalarSuffix == "U32":
      ident"deserializeBincodeU32"
    else:
      ident("deserializeBincode" & info.scalarSuffix)
  of fkEnum:
    ident"deserializeBincodeEnumDiscriminant"
  of fkSeq, fkArray, fkObject, fkBytesNewtype:
    error("decodeProcFor: use composite decode for " & $info.kind)

func buildDecodeField(
    fieldName: NimNode, tmpSym: NimNode, info: TypeInfo,
    dataSym, configSym, offSym: NimNode, fieldTyp: NimNode = nil,
    lengthPrefixed: bool = false,
): NimNode =
  let nSym = newIdentNode("bn_" & $fieldName)
  case info.kind
  of fkBool, fkString, fkChar, fkScalar, fkSeqByte:
    let dec = decodeProcFor(info)
    quote do:
      let (`tmpSym`, `nSym`) = `dec`(`dataSym`, `configSym`, `offSym`)
      `offSym` += `nSym`
  of fkEnum:
    let discSym = bindIdent("disc")
    let enumTy = info.typeSym
    quote do:
      let (`tmpSym`, `nSym`) = block:
        let (`discSym`, n0) =
          deserializeBincodeEnumDiscriminant(`dataSym`, `configSym`, `offSym`)
        (cast[`enumTy`](int(`discSym`)), n0)
      `offSym` += `nSym`
  of fkSeq:
    let fq =
      block:
        let id = fieldIdent(fieldName)
        if id.kind == nnkIdent and $id == "_":
          "_root"
        else:
          $id
    let lenValSym = bindIdent("lenVal_" & fq)
    let nLenSym = bindIdent("nLen_" & fq)
    let itemSym = bindIdent("item_" & fq)
    let nItemSym = bindIdent("nItem_" & fq)
    let elemInfo = classifyType(info.elemType)
    let elemT = skipTypeModifiers(info.elemType)
    if elemInfo.kind == fkObject:
      let elemAt = bincodeDeserializeAtName(elemInfo.typeSym)
      quote do:
        let (`lenValSym`, `nLenSym`) =
          decodeLength(`dataSym`.toOpenArray(`offSym`, `dataSym`.high), `configSym`)
        `offSym` += `nLenSym`
        var `tmpSym` = newSeq[`elemT`](`lenValSym`.int)
        for i in 0 ..< `tmpSym`.len:
          let (`itemSym`, `nItemSym`) = `elemAt`(`dataSym`, `configSym`, `offSym`)
          `offSym` += `nItemSym`
          `tmpSym`[i] = `itemSym`
    elif elemInfo.kind == fkArray:
      let inner = classifyType(elemInfo.elemType)
      let innerDec = decodeProcFor(inner)
      let n = elemInfo.arrayLen
      quote do:
        let (`lenValSym`, `nLenSym`) =
          decodeLength(`dataSym`.toOpenArray(`offSym`, `dataSym`.high), `configSym`)
        `offSym` += `nLenSym`
        var `tmpSym` = newSeq[`elemT`](`lenValSym`.int)
        for i in 0 ..< `tmpSym`.len:
          for j in 0 ..< `n`:
            let (b, nb) = `innerDec`(`dataSym`, `configSym`, `offSym`)
            `offSym` += nb
            `tmpSym`[i][j] = b
    elif elemInfo.kind == fkBytesNewtype:
      let n = newtypeDataArrayBracket(elemT)[1]
      let innerDec = ident"deserializeBincodeU8"
      quote do:
        let (`lenValSym`, `nLenSym`) =
          decodeLength(`dataSym`.toOpenArray(`offSym`, `dataSym`.high), `configSym`)
        `offSym` += `nLenSym`
        var `tmpSym` = newSeq[`elemT`](`lenValSym`.int)
        for i in 0 ..< `tmpSym`.len:
          for j in 0 ..< `n`:
            let (b, nb) = `innerDec`(`dataSym`, `configSym`, `offSym`)
            `offSym` += nb
            `tmpSym`[i].data[j] = b
    else:
      let elemDec = decodeProcFor(elemInfo)
      quote do:
        let (`lenValSym`, `nLenSym`) =
          decodeLength(`dataSym`.toOpenArray(`offSym`, `dataSym`.high), `configSym`)
        `offSym` += `nLenSym`
        var `tmpSym` = newSeq[`elemT`](`lenValSym`.int)
        for i in 0 ..< `tmpSym`.len:
          let (`itemSym`, `nItemSym`) = `elemDec`(`dataSym`, `configSym`, `offSym`)
          `offSym` += `nItemSym`
          `tmpSym`[i] = `itemSym`
  of fkArray:
    let n = info.arrayLen
    if lengthPrefixed and isByteElemType(info.elemType):
      quote do:
        let (blob, nb) = decodePrefixedByteSeq(`dataSym`, `configSym`, `offSym`)
        `offSym` += nb
        if blob.len != int(`n`):
          raise newException(BincodeError, "fixed byte array length mismatch")
        for i in 0 ..< int(`n`):
          `tmpSym`[i] = blob[i]
    else:
      let elemInfo = classifyType(info.elemType)
      let itemSym = bindIdent("item")
      let nItemSym = bindIdent("nItem")
      if elemInfo.kind == fkObject:
        let elemAt = bincodeDeserializeAtName(elemInfo.typeSym)
        quote do:
          for i in 0 ..< `n`:
            let (`itemSym`, `nItemSym`) = `elemAt`(`dataSym`, `configSym`, `offSym`)
            `offSym` += `nItemSym`
            `tmpSym`[i] = `itemSym`
      else:
        let elemDec = decodeProcFor(elemInfo)
        quote do:
          for i in 0 ..< `n`:
            let (`itemSym`, `nItemSym`) = `elemDec`(`dataSym`, `configSym`, `offSym`)
            `offSym` += `nItemSym`
            `tmpSym`[i] = `itemSym`
  of fkBytesNewtype:
    let ft = newtypeDataArrayBracket(fieldTyp)
    let n = ft[1]
    let dataAccess = newTree(nnkDotExpr, tmpSym, bindIdent("data"))
    if lengthPrefixed:
      quote do:
        var `tmpSym`: `fieldTyp`
        let (blob, nb) = decodePrefixedByteSeq(`dataSym`, `configSym`, `offSym`)
        `offSym` += nb
        if blob.len != int(`n`):
          raise newException(BincodeError, "bytes newtype length mismatch")
        for i in 0 ..< int(`n`):
          `dataAccess`[i] = blob[i]
    else:
      let arrInfo = TypeInfo(
        kind: fkArray, arrayLen: ft[1], elemType: newIdentNode("by" & "te")
      )
      newStmtList(
        quote do:
          var `tmpSym`: `fieldTyp`
        ,
        buildDecodeField(
          fieldName, dataAccess, arrInfo, dataSym, configSym, offSym,
          lengthPrefixed = lengthPrefixed,
        ),
      )
  of fkObject:
    let deserAt = bincodeDeserializeAtName(info.typeSym)
    quote do:
      let (`tmpSym`, `nSym`) = `deserAt`(`dataSym`, `configSym`, `offSym`)
      `offSym` += `nSym`

proc bincodeCaseElse*(message: string): NimNode =
  let msg = newLit(message)
  newTree(
    nnkElse,
    quote do:
      raise newException(BincodeError, `msg`)
  )

proc branchOrdinal(branch: NimNode): NimNode =
  if branch.kind == nnkOfBranch:
    if branch[0].kind == nnkIdent:
      return branch[0]
    if branch[0].kind == nnkRange:
      return branch[0][0]
  branch

proc genArrayAliasSerialize(
    typeSym: NimNode, arrayBody: NimNode, lengthPrefixed: bool
): NimNode =
  let info = TypeInfo(kind: fkArray, arrayLen: arrayBody[1], elemType: arrayBody[2])
  let streamId = bindIdent("stream")
  let valueId = bindIdent("value")
  let configId = bindIdent("config")
  let body = buildSerializeAccess(
    info, valueId, streamId, configId, lengthPrefixed = lengthPrefixed
  )
  let serName = bincodeSerializeName(typeSym)
  quote do:
    proc `serName`*(
        `streamId`: OutputStreamHandle, `valueId`: `typeSym`,
        `configId`: BincodeConfig = standard()
    ) {.raises: [BincodeError, IOError].} =
      `body`

proc genArrayAliasDeserializeAt(
    typeSym: NimNode, arrayBody: NimNode, lengthPrefixed: bool
): NimNode =
  let info = TypeInfo(kind: fkArray, arrayLen: arrayBody[1], elemType: arrayBody[2])
  let dataId = bindIdent("data")
  let configId = bindIdent("config")
  let offId = bindIdent("off")
  let startId = bindIdent("start")
  let resultSym = bindIdent("bcResult")
  let decodeStmts = buildDecodeField(
    newIdentNode("_"), resultSym, info, dataId, configId, offId,
    lengthPrefixed = lengthPrefixed,
  )
  let deserAtName = bincodeDeserializeAtName(typeSym)
  quote do:
    func `deserAtName`*(
        `dataId`: openArray[byte], `configId`: BincodeConfig, `startId`: int = 0
    ): (`typeSym`, int) {.raises: [BincodeError].} =
      var `offId` = `startId`
      var `resultSym`: `typeSym`
      `decodeStmts`
      return (`resultSym`, `offId` - `startId`)

proc genEnumSerialize(typeSym, impl: NimNode): NimNode =
  let serName = bincodeSerializeName(typeSym)
  let streamId = bindIdent("stream")
  let valueId = bindIdent("value")
  let configId = bindIdent("config")
  quote do:
    proc `serName`*(
        `streamId`: OutputStreamHandle, `valueId`: `typeSym`,
        `configId`: BincodeConfig = standard()
    ) {.raises: [BincodeError, IOError].} =
      serializeBincodeEnumDiscriminant(
        `streamId`, ord(`valueId`).int, `configId`)

proc genEnumDeserializeAt(typeSym, impl: NimNode): NimNode =
  let deserAtName = bincodeDeserializeAtName(typeSym)
  quote do:
    func `deserAtName`*(
        data: openArray[byte], config: BincodeConfig, start: int = 0
    ): (`typeSym`, int) {.raises: [BincodeError].} =
      var off = start
      let (disc, n0) = deserializeBincodeEnumDiscriminant(data, config, off)
      off += n0
      if uint32(disc) > uint32(high(`typeSym`)):
        raise newException(BincodeError, "Unknown enum discriminant")
      let value = cast[`typeSym`](int(disc))
      return (value, off - start)

proc genObjectSerialize(
    typeSym: NimNode, typeImpl: NimNode, fields: seq[FieldDescription],
    lengthPrefixed: bool,
): NimNode =
  let streamId = bindIdent("stream")
  let valueId = bindIdent("value")
  let configId = bindIdent("config")
  var hasCase = false
  for f in fields:
    if f.caseField != nil:
      hasCase = true
      break

  if not hasCase:
    var body = newStmtList()
    for f in fields:
      if f.caseField != nil:
        continue
      let acc = newTree(nnkDotExpr, valueId, fieldIdent(f.name))
      body.add buildSerializeAccess(
        classifyType(f.typ), acc, streamId, configId, f.typ, lengthPrefixed
      )
    let serName = bincodeSerializeName(typeSym)
    quote do:
      proc `serName`*(
          `streamId`: OutputStreamHandle, `valueId`: `typeSym`,
          `configId`: BincodeConfig = standard()
      ) {.raises: [BincodeError, IOError].} =
        `body`
  else:
    var caseFieldRaw: NimNode
    for f in fields:
      if f.caseField != nil:
        caseFieldRaw = f.caseField
        break
    let caseFieldName = caseFieldIdent(caseFieldRaw)
    var branchMap = initOrderedTable[string, seq[FieldDescription]]()
    for f in fields:
      if f.caseField == nil:
        continue
      let key = f.caseBranch.repr
      branchMap.mgetOrPut(key, @[]).add f

    var caseStmt = newTree(nnkCaseStmt, newDotExpr(valueId, caseFieldName))
    for branch in collectRecCaseBranches(objectTypeBody(typeImpl)):
      let branchId = branchOrdinal(branch)
      let key = branch.repr
      var armBody = newStmtList(
        newCall(
          ident"serializeBincodeEnumDiscriminant",
          streamId,
          newCall(ident"int", newCall(ident"ord", branchId)),
          configId,
        ),
      )
      for f in branchMap.getOrDefault(key):
        let acc = newTree(nnkDotExpr, valueId, fieldIdent(f.name))
        armBody.add buildSerializeAccess(
          classifyType(f.typ), acc, streamId, configId, f.typ, lengthPrefixed
        )
      caseStmt.add newTree(nnkOfBranch, branchId, armBody)

    let serName = bincodeSerializeName(typeSym)
    quote do:
      proc `serName`*(
          `streamId`: OutputStreamHandle, `valueId`: `typeSym`,
          `configId`: BincodeConfig = standard()
      ) {.raises: [BincodeError, IOError].} =
        `caseStmt`

proc genObjectDeserializeAt(
    typeSym: NimNode, typeImpl: NimNode, fields: seq[FieldDescription],
    lengthPrefixed: bool,
): NimNode =
  let dataId = bindIdent("data")
  let configId = bindIdent("config")
  let offId = bindIdent("off")
  let startId = bindIdent("start")
  var hasCase = false
  for f in fields:
    if f.caseField != nil:
      hasCase = true
      break

  if not hasCase:
    var decodeStmts = newStmtList()
    var assignStmts = newStmtList()
    let resultSym = bindIdent("bcResult")
    for f in fields:
      if f.caseField != nil:
        continue
      let info = classifyType(f.typ)
      let fname = fieldIdent(f.name)
      if info.kind in {fkArray, fkBytesNewtype}:
        let access = newDotExpr(resultSym, fname)
        if info.kind == fkBytesNewtype:
          let tmpId = newIdentNode("bc_" & $fname)
          decodeStmts.add buildDecodeField(
            fname, tmpId, info, dataId, configId, offId, f.typ, lengthPrefixed
          )
          assignStmts.add newTree(
            nnkAsgn, newDotExpr(resultSym, fname), tmpId
          )
        else:
          decodeStmts.add buildDecodeField(
            fname, access, info, dataId, configId, offId, f.typ, lengthPrefixed
          )
      else:
        let tmpId = newIdentNode("bc_" & $fname)
        decodeStmts.add buildDecodeField(
          fname, tmpId, info, dataId, configId, offId, f.typ, lengthPrefixed
        )
        assignStmts.add newTree(
          nnkAsgn, newDotExpr(resultSym, fname), tmpId
        )
    let deserAtName = bincodeDeserializeAtName(typeSym)
    quote do:
      func `deserAtName`*(
          `dataId`: openArray[byte], `configId`: BincodeConfig, `startId`: int = 0
      ): (`typeSym`, int) {.raises: [BincodeError].} =
        var `offId` = `startId`
        var `resultSym`: `typeSym`
        `decodeStmts`
        `assignStmts`
        return (`resultSym`, `offId` - `startId`)
  else:
    var caseFieldRaw: NimNode
    for f in fields:
      if f.caseField != nil:
        caseFieldRaw = f.caseField
        break
    let caseFieldName = caseFieldIdent(caseFieldRaw)
    var branchMap = initOrderedTable[string, seq[FieldDescription]]()
    for f in fields:
      if f.caseField == nil:
        continue
      let key = f.caseBranch.repr
      branchMap.mgetOrPut(key, @[]).add f

    var caseArms = newStmtList()
    for branch in collectRecCaseBranches(objectTypeBody(typeImpl)):
      let branchId = branchOrdinal(branch)
      let key = branch.repr
      var decodeStmts = newStmtList()
      var assignStmts = newStmtList()
      let resultSym = bindIdent("bcResult")
      for f in branchMap.getOrDefault(key):
        let info = classifyType(f.typ)
        let fname = fieldIdent(f.name)
        if info.kind in {fkArray, fkBytesNewtype}:
          if info.kind == fkBytesNewtype:
            let tmpId = newIdentNode("bc_" & $fname)
            decodeStmts.add buildDecodeField(
              fname, tmpId, info, dataId, configId, offId, f.typ, lengthPrefixed
            )
            assignStmts.add newTree(nnkAsgn, newDotExpr(resultSym, fname), tmpId)
          else:
            let access = newDotExpr(resultSym, fname)
            decodeStmts.add buildDecodeField(
              fname, access, info, dataId, configId, offId, f.typ, lengthPrefixed
            )
        else:
          let tmpId = newIdentNode("bc_" & $fname)
          decodeStmts.add buildDecodeField(
            fname, tmpId, info, dataId, configId, offId, f.typ, lengthPrefixed
          )
          assignStmts.add newTree(nnkAsgn, newDotExpr(resultSym, fname), tmpId)
      var armStmt = newStmtList()
      armStmt.add quote do:
        var `resultSym` = `typeSym`(kind: `branchId`)
      for s in decodeStmts:
        armStmt.add s
      for s in assignStmts:
        armStmt.add s
      armStmt.add quote do:
        ( `resultSym`, `offId` - `startId` )
      caseArms.add newTree(
        nnkOfBranch,
        newCall("uint32", newCall("ord", branchId)),
        armStmt,
      )

    let elseArm = bincodeCaseElse("Unknown variant discriminant")
    let discId = bindIdent("disc")
    var caseStmt = newTree(nnkCaseStmt, discId)
    for arm in caseArms:
      caseStmt.add arm
    caseStmt.add elseArm
    let deserAtName = bincodeDeserializeAtName(typeSym)
    quote do:
      func `deserAtName`*(
          `dataId`: openArray[byte], `configId`: BincodeConfig, `startId`: int = 0
      ): (`typeSym`, int) {.raises: [BincodeError].} =
        var `offId` = `startId`
        let (`discId`, n0) = deserializeBincodeEnumDiscriminant(`dataId`, `configId`, `offId`)
        `offId` += n0
        let (value, used) = `caseStmt`
        return (value, used)

proc genWrapperDeserialize(typeSym: NimNode): NimNode =
  let deserName = bincodeDeserializeName(typeSym)
  let deserAtName = bincodeDeserializeAtName(typeSym)
  quote do:
    func `deserName`*(
        data: openArray[byte], config: BincodeConfig = standard()
    ): `typeSym` {.raises: [BincodeError].} =
      let (value, used) = `deserAtName`(data, config, 0)
      if used != data.len:
        raise newException(BincodeError, "Trailing bytes after value")
      value

var deriveBincodeImportsEmitted {.compileTime.} = false

macro deriveBincode*(
    typ: typed, lengthPrefixed: static[bool] = false
): untyped =
  ## Generate ``serializeType`` / ``deserialize`` procs for a type.
  ##
  ## ``lengthPrefixed`` (default ``false``): when ``true``, fixed byte blobs
  ## (``array[N, byte]`` and ``data: array[N, byte]`` newtypes) are encoded
  ## with a length prefix like Rust ``serialize_bytes``. ``seq``/``string``
  ## fields always use a prefix regardless of this flag.
  let typeName =
    if typ.kind == nnkSym:
      typ
    else:
      error("deriveBincode expects a type, e.g. deriveBincode(Person)")
  let impl = typeName.getImpl()
  impl.expectKind nnkTypeDef
  let body = impl[2]

  var ser, deserAt, deserWrap, toSeq: NimNode
  if body.kind == nnkEnumTy:
    ser = genEnumSerialize(typeName, impl)
    deserAt = genEnumDeserializeAt(typeName, impl)
  elif body.kind in {nnkObjectTy, nnkRefTy}:
    let fields = recordFields(impl)
    ser = genObjectSerialize(typeName, impl, fields, lengthPrefixed)
    deserAt = genObjectDeserializeAt(typeName, impl, fields, lengthPrefixed)
  elif body.kind == nnkBracketExpr:
    let head =
      if body[0].kind == nnkSym:
        $body[0]
      elif body[0].kind == nnkIdent:
        $body[0]
      else:
        ""
    if head != "array":
      error("deriveBincode: unsupported type kind for " & $typeName)
    ser = genArrayAliasSerialize(typeName, body, lengthPrefixed)
    deserAt = genArrayAliasDeserializeAt(typeName, body, lengthPrefixed)
  else:
    error("deriveBincode: unsupported type kind for " & $typeName)

  deserWrap = genWrapperDeserialize(typeName)
  let serName = bincodeSerializeName(typeName)
  let toSeqName = bincodeSerializeToSeqName(typeName)
  toSeq = quote do:
    proc `toSeqName`*(
        value: `typeName`, config: BincodeConfig = standard()
    ): seq[byte] {.raises: [BincodeError, IOError].} =
      var stream = memoryOutput()
      `serName`(stream, value, config)
      stream.getOutput()

  result = newStmtList()
  if not deriveBincodeImportsEmitted:
    deriveBincodeImportsEmitted = true
    result.add quote do:
      import bincode_common
      import bincode_config
      import bincode_fields
      import faststreams
  result.add ser
  result.add deserAt
  result.add deserWrap
  result.add toSeq

{.pop.}
