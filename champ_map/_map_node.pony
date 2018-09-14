
use col = "collections"

type _MapLeaf[K: Any #share, V: Any #share, H: col.HashFunction[K] val]
  is (K, V)

type _MapBucket[K: Any #share, V: Any #share, H: col.HashFunction[K] val]
  is Array[_MapLeaf[K, V, H]] val

type _MapEntry[K: Any #share, V: Any #share, H: col.HashFunction[K] val]
  is (_MapNode[K, V, H] | _MapBucket[K, V, H] | _MapLeaf[K, V, H])

class val _MapNode[K: Any #share, V: Any #share, H: col.HashFunction[K] val]
  let _entries: Array[_MapEntry[K, V, H]] iso
  let _bitmap: USize

  new val empty() =>
    _entries = recover iso Array[_MapEntry[K, V, H]](0) end
    _bitmap = 0

  new val create(entries: Array[_MapEntry[K, V, H]] iso, bitmap: USize) =>
    _entries = consume entries
    _bitmap = bitmap

  fun val debug(str: String iso, level: USize,
    pk: {(K, String iso): String iso^}, pv: {(V, String iso): String iso^})
    : String iso^
  =>
    var str': String iso = consume str
    for _ in col.Range(0, level) do str'.append("  ") end
    str'.append("{ " + level.string() + " < ")
    for bit in col.Range(0, USize(0).bitwidth()) do
      if ((USize(1) << bit) and _bitmap) != 0 then
        str'.append(bit.string())
        str'.append(" ")
      end
    end
    str'.append(">\n")

    var i: USize = 0
    for entry in _entries.values() do
      if i > 0 then
        str'.append(",\n")
      end
      match entry
      | (let k: K, let v: V) =>
        for _ in col.Range(0, level+1) do str'.append("  ") end
        str'.append("(")
        str' = pk(k, consume str')
        str'.append(", ")
        str' = pv(v, consume str')
        str'.append(")")
      | let node: _MapNode[K, V, H] =>
        str' = node.debug(consume str', level+1, pk, pv)
      | let bucket: _MapBucket[K, V, H] =>
        for _ in col.Range(0, level+1) do str'.append("  ") end
        str'.append("[")
        var j: USize = 0
        for value in bucket.values() do
          if j > 0 then
            str'.append(", ")
          end
          str'.append("(")
          str' = pk(value._1, consume str')
          str'.append(", ")
          str' = pv(value._2, consume str')
          str'.append(")")
          j = j + 1
        end
        str'.append("]")
      end
      i = i + 1
    end
    str'.append("\n")
    for _ in col.Range(0, level) do str'.append("  ") end
    str'.append("}")
    consume str'

  fun val apply(key: K, hash: USize, level: USize): V ? =>
    let msk = Bits.mask(hash, level)
    let bit = Bits.bitpos(hash, level)
    let idx = Bits.index(_bitmap, bit)
    match _entries(idx)?
    | (let k: K, let v: V) =>
      if H.eq(k, key) then
        v
      else
        error
      end
    | let node: _MapNode[K, V, H] =>
      node(key, hash, level + 1)?
    | let bucket: _MapBucket[K, V, H] =>
      for entry in bucket.values() do
        if H.eq(entry._1, key) then
          return entry._2
        end
      end
      error
    end

  fun val update(key: K, hash: USize, value: V, level: USize)
    : (_MapNode[K, V, H], Bool) ?
  =>
    let msk = Bits.mask(hash, level)
    let bit = Bits.bitpos(hash, level)
    let idx = Bits.index(_bitmap, bit)
    if idx < _entries.size() then
      // there is already an entry at the index in our array
      match _entries(idx)?
      | (let existing_key: K, let existing_value: V) =>
        // entry is a value
        if H.eq(key, existing_key) then
          // it's the same key, replace it
          let new_entries = recover iso _entries.clone() end
          new_entries.update(idx, (key, value))?
          (_MapNode[K, V, H](consume new_entries, _bitmap), false)
        elseif level == Bits.max_level() then
          // we don't have any hash left, make a new bucket
          let new_bucket =
            recover val
              let bb = _MapBucket[K, V, H](2)
              bb.push((existing_key, existing_value))
              bb.>push((key, value))
            end
          let new_entries = recover iso _entries.clone() end
          new_entries.update(idx, new_bucket)?
          (_MapNode[K, V, H](consume new_entries, _bitmap), true)
        else
          // make a new node with the original value and ours
          var sub_node = _MapNode[K, V, H].empty()
          (sub_node, _) = sub_node.update(existing_key, H.hash(existing_key),
            existing_value, level+1)?
          (sub_node, _) = sub_node.update(key, hash, value, level + 1)?

          let new_entries = recover iso _entries.clone() end
          new_entries.update(idx, sub_node)?
          (_MapNode[K, V, H](consume new_entries, _bitmap), true)
        end
      | let node: _MapNode[K, V, H] =>
        // entry is a node, update it recursively
        (let new_node, let inserted) = node.update(key, hash, value, level + 1)?
        let new_entries = recover iso _entries.clone() end
        new_entries.update(idx, new_node)?
        (_MapNode[K, V, H](consume new_entries, _bitmap), inserted)
      | let bucket: _MapBucket[K, V, H] =>
        // entry is a bucket; add our value to it
        let new_bucket =
          recover val
            let nb = bucket.clone()
            nb.push((key, value))
            nb
          end
        let new_entries = recover iso _entries.clone() end
        new_entries.update(idx, new_bucket)?
        (_MapNode[K, V, H](consume new_entries, _bitmap), true)
      end
    else
      // there is no entry in our array; add one
      let new_bitmap = _bitmap or bit
      let new_idx = Bits.index(new_bitmap, bit)
      let new_entries =
        recover iso
          let es = Array[_MapEntry[K, V, H]](_entries.size() + 1)
          _entries.copy_to(es, 0, 0, _entries.size())
          es.insert(new_idx, (key, value))?
          es
        end
      (_MapNode[K, V, H](consume new_entries, new_bitmap), true)
    end

  fun val remove(key: K, hash: USize, level: USize)
    : (_MapNode[K, V, H] | _MapLeaf[K, V, H] | _NodeRemoved) ?
  =>
    let msk = Bits.mask(hash, level)
    let bit = Bits.bitpos(hash, level)
    let idx = Bits.index(_bitmap, bit)
    match _entries(idx)?
    | (let k: K, let v: V) =>
      // hash matches a leaf
      if not H.eq(k, key) then
        error
      end
      if (level != 0) and (_entries.size() <= 2) then
        if _entries.size() == 1 then
          _NodeRemoved
        else
          let entry = _entries(1 - idx)?
          match entry
          | let leaf: _MapLeaf[K, V, H] =>
            leaf
          else
            _MapNode[K, V, H]([entry], _bitmap and (not bit))
          end
        end
      else
        let es = recover _entries.clone() end
        es.delete(idx)?
        _MapNode[K, V, H](consume es, _bitmap and (not bit))
      end
    | let node: _MapNode[K, V, H] =>
      match node.remove(key, hash, level + 1)?
      | _NodeRemoved =>
        // node pointed to a single entry; just remove it
        if (level != 0) and (_entries.size() <= 2) then
          if _entries.size() == 1 then
            _NodeRemoved
          else
            let entry = _entries(1 - idx)?
            match entry
            | let leaf: _MapLeaf[K, V, H] =>
              leaf
            else
              _MapNode[K, V, H]([entry], _bitmap and (not bit))
            end
          end
        else
          let es = recover _entries.clone() end
          es.delete(idx)?
          _MapNode[K, V, H](consume es, _bitmap and (not bit))
        end
      | let entry: _MapEntry[K, V, H] =>
        let es = recover _entries.clone() end
        es(idx)? = entry
        _MapNode[K, V, H](consume es, _bitmap)
      end
    | let bucket: _MapBucket[K, V, H] =>
      // remove us from the bucket
      let bs =
        recover val
          let bs' = _MapBucket[K, V, H](bucket.size())
          for entry in bucket.values() do
            if not H.eq(entry._1, key) then
              bs'.push(entry)
            end
          end
          bs'
        end
      if bs.size() == bucket.size() then
        // we didn't find our entry
        error
      end
      if (level != 0) and (bs.size() == 0) then
        // remove this node from the node above
        _NodeRemoved
      else
        // remove entry from the bucket
        let es = recover _entries.clone() end
        es(idx)? = bs
        _MapNode[K, V, H](consume es, _bitmap)
      end
    end

primitive _NodeRemoved
