import metadata
import json
import algorithm
import strutils
import tables

# todo: use int64 for start and finish.

type
  OffsetList* = seq[tuple[start: uint32, finish: uint32]]

  Range* = object
    start*: uint32
    finish*: uint32
    name*: string
    message*: string
    known*: bool  ## \\
    ## A range describes a section of the file.  The start is the
    ## offset of the beginning of the section and finish is one past
    ## the end. The known field is true when the section format is
    ## known and handled by the current code, false when the format of
    ## the section is unknown.


proc newRange*(start: uint32, finish: uint32, name: string = "",
               known: bool = true, message: string = ""): Range =
  result = Range(start: start, finish: finish, name: name, known: known, message: message)


proc mergeOffsets*(ranges: seq[Range], paddingShift: Natural = 0):
    tuple[minList: OffsetList, gapList: OffsetList] =
  ## Given a list of ranges, merge them into the smallest set of
  ## contiguous ranges. Return the new list of ranges. Also return a
  ## list of ranges that cover the gaps.  You can add the ranges (0,0)
  ## or (totalSize, totalSize) to the range list to cover the
  ## beginning and end of the file. The paddingShift number determines
  ## the end of the padding. 0 is no padding, 1 align on even
  ## boundaries, 2 align on 4 bit boundaries, etc.

  var minList = newSeq[tuple[start: uint32, finish: uint32]]()
  var gapList = newSeq[tuple[start: uint32, finish: uint32]]()

  if ranges.len == 0:
    result = (minList, gapList)
    return

  # Sort the ranges by the start offset.
  let sortedRanges = ranges.sortedByIt(it.start)

  var start = ranges[0].start
  var finish = ranges[0].finish

  for ix in 1..sortedRanges.len-1:
    let range = sortedRanges[ix]
    let r_start = range.start
    let r_finish = range.finish

    var boundary: uint32
    if paddingShift > 0:
      boundary = ((finish shr paddingShift) + 1) shl paddingShift

    if finish >= r_start or (paddingShift > 0 and boundary == r_start):
      # Contiguous, ovelapping range or padding, merge.
      if r_finish > finish:
        finish = r_finish
    else:
      # Found a gap
      if start < finish:
        minList.add((start, finish))
      gapList.add((finish, r_start))
      start = r_start
      finish = r_finish

  if start < finish:
    minList.add((start, finish))
  result = (minList, gapList)


proc readGap*(file: File, start: uint32, finish: uint32): string =
  ## Read the range of the file and return a short hex representation.

  let count = (int)(finish - start)
  var readCount: int
  if count > 8:
     readCount = 8
  else:
    readCount = count
  var buffer = newSeq[uint8](readCount)
  file.setFilePos((int64)start)
  if file.readBytes(buffer, 0, readCount) != readCount:
    raise newException(NotSupportedError, "Unable to read all the gap bytes.")

  #todo: remove the error prefix from all error messages.

  if count == 1:
    result = $count & " gap byte:"
  else:
    result = $count & " gap bytes:"

  for item in buffer:
    result.add(" $1" % [toHex(item)])
  if count != readCount:
    result.add("...")
  result.add("  ")
  for ascii in buffer:
    if ascii >= 0x20'u8 and ascii <= 0x7f'u8:
      result.add($char(ascii))
    else:
      result.add(".")


# proc cmpRanges(one: Range, two: Range): int =
#   if one.start < two.start:
#     result = -1
#   elif one.start > two.start:
#     result = 1
#   else:
#     result = 0


proc createRangeNode(item: Range): JsonNode =
  ## Create a range node from a range.

  result = newJArray()
  result.add(newJString(item.name))
  result.add(newJInt((BiggestInt)item.start))
  result.add(newJInt((BiggestInt)item.finish))
  result.add(newJBool(item.known))
  result.add(newJString(item.message))


proc createRangesNode*(file: File, start: uint32, finish: uint32,
                       ranges: var seq[Range]): JsonNode =
  ## Create ranges node from a list of ranges. Add in the gaps and
  ## sort the ranges.

  var offsetList = newSeq[Range](ranges.len)
  for ix, item in ranges:
    offsetList[ix] = newRange(item.start, item.finish)
  offsetList.add(newRange(start, start))
  offsetList.add(newRange(finish, finish))
  let (_, gaps) = mergeOffsets(offsetList)
  for start, finish in gaps.items():
    let gapHex = readGap(file, start, finish)
    ranges.add(Range(name: "gap", start: start, finish: finish,
                   known: false, message:gapHex))
  let sortedRanges = ranges.sortedByIt(it.start)

  # Create a ranges node from the ranges list.
  result = newJArray()
  for rangeItem in sortedRanges:
    result.add(createRangeNode(rangeItem))


proc addSection*(metadata: var Metadata, dups: var Table[string, int],
                sectionName: string, info: JsonNode) =
  ## Add the section to the given metadata.  If the section already
  ## exists in the metadata, put it in an array.

  assert(info != nil)

  if sectionName in dups:
    # More than one, store them in an array.
    var existingInfo = metadata[sectionName]
    if existingInfo.kind != JArray:
      var jarray = newJArray()
      jarray.add(existingInfo)
      existingInfo = jarray
    existingInfo.add(info)
    metadata[sectionName] = existingInfo
  else:
    metadata[sectionName] = info
  dups[sectionName] = 1
