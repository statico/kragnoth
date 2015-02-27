{DenseMap, SparseMap} = require './map.coffee'

exports.testSparseMap =

  testSimple: (test) ->
    map = new SparseMap(10, 10)

    map.set 2, 1, 'a'
    map.set 3, 1, 'b'
    map.set 5, 4, 'c'

    test.equal map.get(2, 1), 'a'
    test.equal map.get(3, 1), 'b'
    test.equal map.get(5, 4), 'c'

    map.delete 2, 1
    test.equal map.get(2, 1), null
    test.equal map.get(3, 1), 'b'
    test.equal map.get(5, 4), 'c'

    map.delete 3, 1
    test.equal map.get(2, 1), null
    test.equal map.get(3, 1), null
    test.equal map.get(5, 4), 'c'

    map.delete 5, 4
    test.equal map.get(2, 1), null
    test.equal map.get(3, 1), null
    test.equal map.get(5, 4), null

    test.deepEqual map.map, {}

    test.done()
