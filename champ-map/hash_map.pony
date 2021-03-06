
use col = "collections"

type Map[K: (col.Hashable val & Equatable[K]), V: Any #share] is
  HashMap[K, V, col.HashEq[K]]
  """
  A map that uses structural equality to compare keys.
  """

type MapIs[K: Any #share, V: Any #share] is HashMap[K, V, col.HashIs[K]]
  """
  A map that uses identity to compare keys.
  """

class val HashMap[K: Any #share, V: Any #share, H: col.HashFunction[K] val]
  let _root: _MapNode[K, V, H]
  let _size: USize

  new val create() =>
    _root = _MapNode[K, V, H].empty()
    _size = 0

  new val _create(root: _MapNode[K, V, H], size': USize) =>
    _root = root
    _size = size'

  fun val size(): USize =>
    _size

  fun val apply(k: K): val->V ? =>
    _root(k, H.hash(k), 0)?

  fun val update(key: K, value: V): HashMap[K, V, H] ? =>
    (let node, let inserted) = _root.update(key, H.hash(key), value, 0)?
    _create(node, if inserted then _size + 1 else _size end)

  fun val remove(k: K): HashMap[K, V, H] ? =>
    match _root.remove(k, H.hash(k), 0)?
    | let node: _MapNode[K, V, H] =>
      _create(node, _size - 1)
    else
      error
    end

  fun val get_or_else(k: K, alt: val->V): val->V =>
    try
      apply(k)?
    else
      alt
    end

  fun val contains(k: K): Bool =>
    try
      apply(k)?
      true
    else
      false
    end

  fun val concat(iter: Iterator[(val->K, val->V)]): HashMap[K, V, H] ? =>
    var map = this
    for (k, v) in iter do
      map = map.update(k, v)?
    end
    map

  fun val keys(): MapKeys[K, V, H] =>
    MapKeys[K, V, H](_root, _size)

  fun val values(): MapValues[K, V, H] =>
    MapValues[K, V, H](_root, _size)

  fun val pairs(): MapPairs[K, V, H] =>
    MapPairs[K, V, H](_root, _size)

  fun val debug(str: String iso, pk: {(K, String iso): String iso^},
    pv: {(V, String iso): String iso^}): String iso^
  =>
    try
      _root.debug(consume str, 0, 0, 0, pk, pv)?
    else
      recover iso
        let s = String
        s.append("Error!")
        s
      end
    end
