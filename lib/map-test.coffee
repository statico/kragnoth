{DenseMap, SparseMap, SparseMapList} = require './map.coffee'

exports.testSparseMap =

  testSimple: (test) ->
    map = new SparseMap(10, 10)

    map.set [2, 1], 'a'
    map.set [3, 1], 'b'
    map.set [5, 4], 'c'

    test.equal map.get([2, 1]), 'a'
    test.equal map.get([3, 1]), 'b'
    test.equal map.get([5, 4]), 'c'

    map.delete [2, 1]
    test.equal map.get([2, 1]), null
    test.equal map.get([3, 1]), 'b'
    test.equal map.get([5, 4]), 'c'

    map.delete [3, 1]
    test.equal map.get([2, 1]), null
    test.equal map.get([3, 1]), null
    test.equal map.get([5, 4]), 'c'

    map.delete [5, 4]
    test.equal map.get([2, 1]), null
    test.equal map.get([3, 1]), null
    test.equal map.get([5, 4]), null

    test.deepEqual map.map, {}

    test.done()

exports.testSparseMapList =

  testSimple: (test) ->
    map = new SparseMapList(10, 10)

    map.add [2, 1], 'a'
    map.add [2, 1], 'b'
    map.add [2, 1], 'c'
    map.add [3, 1], 'd'
    map.add [5, 4], 'e'

    test.equal map.isEmpty([0, 0]), true
    test.equal map.isEmpty([2, 1]), false
    test.equal map.isEmpty([3, 1]), false
    test.equal map.isEmpty([5, 4]), false

    test.deepEqual map.get([0, 0]), undefined
    test.deepEqual map.get([2, 1]), ['a', 'b', 'c']
    test.deepEqual map.get([3, 1]), ['d']
    test.deepEqual map.get([5, 4]), ['e']

    map.remove [2, 1], 'b'
    test.equal map.isEmpty([2, 1]), false
    test.deepEqual map.get([2, 1]), ['a', 'c']

    map.delete [2, 1]
    test.equal map.isEmpty([2, 1]), true
    test.deepEqual map.get([2, 1]), undefined

    map.remove [3, 1], 'd'
    test.equal map.isEmpty([3, 1]), true
    test.deepEqual map.get([3, 1]), undefined

    map.remove [3, 1], 'd'
    map.remove [3, 1], 'd'
    map.remove [3, 1], 'd'
    test.equal map.isEmpty([3, 1]), true
    test.deepEqual map.get([3, 1]), undefined

    map.add [8, 8], 'q'
    map.add [8, 8], 'q'
    map.add [8, 8], 'q'
    test.equal map.isEmpty([8, 8]), false
    test.deepEqual map.get([8, 8]), ['q', 'q', 'q']
    map.delete [8, 8]

    map.set [9, 9], ['x', 'y', 'z']
    test.equal map.isEmpty([9, 9]), false
    test.deepEqual map.get([9, 9]), ['x', 'y', 'z']
    map.delete [9, 9]

    map.delete [5, 4]

    test.deepEqual map.map, {}

    test.done()
