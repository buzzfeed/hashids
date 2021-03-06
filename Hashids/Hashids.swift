//
//  HashIds.swift
//  http://hashids.org
//
//  Author https://github.com/malczak
//  Licensed under the MIT license.
//

import Foundation

// MARK: Hashids options

public struct HashidsOptions {
    static let VERSION = "1.1.0"
    
    static var MIN_ALPHABET_LENGTH: Int = 16
    
    static var SEP_DIV: Double = 3.5
    
    static var GUARD_DIV: Double = 12
    
    static var ALPHABET: String = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890"
    
    static var SEPARATORS: String = "cfhistuCFHISTU"
}


// MARK: Hashids protocol

public protocol HashidsGenerator {
    associatedtype Char
    
    func encode(value: Int64...) -> String?
    
    func encode(values: [Int64]) -> String?
    
    func encode(values: [Int]) -> String?
    
    func encode(value: Int...) -> String?
    
    func decode64(value: String) -> [Int64]
    
    func decode64(value: [Char]) -> [Int64]
    
    func decode(value: String) -> [Int]
    
    func decode(value: [Char]) ->  [Int]
}


// MARK: Hashids class

public typealias Hashids = Hashids_<UInt32>


// MARK: Hashids generic class

public class Hashids_<T: protocol<Equatable, UnsignedIntegerType>>: HashidsGenerator {
    public typealias Char = T
    
    private var minHashLength: UInt
    
    private var alphabet: [Char]
    
    private var seps: [Char]

    private var salt: [Char]
    
    private var guards: [Char]
    
    public init(salt: String, minHashLength: UInt = 0, alphabet: String? = nil) {
        let _alphabet = alphabet ?? HashidsOptions.ALPHABET
        var _seps = HashidsOptions.SEPARATORS
        
        self.minHashLength = minHashLength
        self.guards = [Char]()
        self.salt = salt.unicodeScalars.map{ numericCast($0.value) }
        self.seps = _seps.unicodeScalars.map{ numericCast($0.value) }
        self.alphabet = unique( _alphabet.unicodeScalars.map{ numericCast($0.value) } )
        
        self.seps = intersection(self.alphabet, self.seps)
        self.alphabet = difference(self.alphabet, self.seps)
        shuffle(&self.seps, salt: self.salt)

        
        let sepsLength = self.seps.count
        let alphabetLength = self.alphabet.count
        
        if (0 == sepsLength) || (Double(alphabetLength) / Double(sepsLength) > HashidsOptions.SEP_DIV) {
            
            var newSepsLength = Int(ceil(Double(alphabetLength) / HashidsOptions.SEP_DIV))
            
            if 1 == newSepsLength {
                newSepsLength += 1
            }
            
            if newSepsLength > sepsLength {
                let diff = self.alphabet.startIndex.advancedBy(newSepsLength - sepsLength)
                let range = 0..<diff
                self.seps += self.alphabet[range]
                self.alphabet.removeRange(range)
            } else {
                let pos = self.seps.startIndex.advancedBy(newSepsLength)
                self.seps.removeRange(pos+1..<self.seps.count)
            }
        }
        
        shuffle(&self.alphabet, salt: self.salt)
        
        let safeGuard = Int(ceil(Double(alphabetLength)/HashidsOptions.GUARD_DIV))
        if alphabetLength < 3 {
            let seps_guard = self.seps.startIndex.advancedBy(safeGuard)
            let range = 0..<seps_guard
            self.guards += self.seps[range]
            self.seps.removeRange(range)
        } else {
            let alphabet_guard = self.alphabet.startIndex.advancedBy(safeGuard)
            let range = 0..<alphabet_guard
            self.guards += self.alphabet[range]
            self.alphabet.removeRange(range)
        }
    }
    
    // MARK: public api

    public func encode(value: Int64...) -> String? {
        return encode(value)
    }
    
    public func encode(values: [Int64]) -> String? {
        let ret = _encode(values)
        return ret.reduce(String(), combine: { (so, i) in
            var so = so
            let scalar:UInt32 = numericCast(i)
            so.append(UnicodeScalar(scalar))
            return so
        })
    }
    
    public func encode(value: Int...) -> String? {
        return encode(value)
    }
    
    public func encode(values: [Int]) -> String? {
        return encode(values.map { Int64($0) })
    }
    
    public func decode64(value: String) -> [Int64] {
        let trimmed = value.stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceAndNewlineCharacterSet())
        let hash: [Char] = trimmed.unicodeScalars.map{ numericCast($0.value) }
        return self.decode64(hash)
    }
    
    public func decode(value: String) -> [Int] {
        return self.decode64(value).map { Int($0) }
    }
    
    public func decode64(value: [Char]) -> [Int64] {
        return self._decode(value)
    }
    
    public func decode(value: [Char]) -> [Int] {
        return self._decode(value).map{ Int($0) }
    }
    
    // MARK: private funcitons 
    
    private func _encode(numbers: [Int64]) -> [Char] {
        var alphabet = self.alphabet
        var numbers_hash_int: Int64 = 0

        for (index, value) in numbers.enumerate() {
            numbers_hash_int += value % ( index + 100 )
        }
        
        let lottery = alphabet[Int(numbers_hash_int % Int64(alphabet.count))]
        var hash = [lottery]
  
        var lsalt = [Char]()
        let (lsaltARange, lsaltRange) = _saltify(&lsalt, lottery: lottery, alphabet: alphabet)
        
        for (index, value) in numbers.enumerate() {
            shuffle(&alphabet, salt: lsalt, saltRange: lsaltRange)
            let lastIndex = hash.endIndex
            _hash(&hash, number: value, alphabet: alphabet)
            
            if index + 1 < numbers.count  {
                let number = value % Int64((numericCast(hash[lastIndex]) + index))
                let seps_index = number % Int64(self.seps.count)
                hash.append(self.seps[Int(seps_index)])
            }
            
            lsalt.replaceRange(lsaltARange, with: alphabet)
        }
        
        let minLength: Int = numericCast(self.minHashLength)
        
        if hash.count < minLength {
            let guard_index = (numbers_hash_int + numericCast(hash[0])) % Int64(self.guards.count)
            let safeGuard = self.guards[Int(guard_index)]
            hash.insert(safeGuard, atIndex: 0)
            
            if hash.count < minLength {
                let guard_index = (numbers_hash_int + numericCast(hash[2])) % Int64(self.guards.count)
                let safeGuard = self.guards[Int(guard_index)]
                hash.append(safeGuard)
            }
        }
        
        let half_length = alphabet.count >> 1
        while hash.count < minLength {
            shuffle(&alphabet, salt: alphabet)
            let lrange = 0..<half_length
            let rrange = half_length..<(alphabet.count)
            hash = alphabet[rrange] + hash + alphabet[lrange]
            
            let excess = hash.count - minLength
            if excess > 0 {
                let start = excess >> 1
                hash = [Char](hash[start..<(start+minLength)])
            }
        }
        
        return hash
    }
    
    private func _decode(hash: [Char]) -> [Int64] {
        var ret = [Int64]()
        
        var alphabet = self.alphabet
        
        var hashes = hash.split(hash.count, allowEmptySlices: true) {
            self.guards.contains($0)
        }
        
        let hashesCount = hashes.count, i = ( hashesCount == 2 || hashesCount == 3) ? 1 : 0
        let hash = hashes[i]
        
        if !hash.isEmpty {
            let lottery = hash[hash.startIndex]
            let valuesHashes = hash[1..<hash.count]
            let valueHashes = valuesHashes.split(valuesHashes.count, allowEmptySlices: true) { self.seps.contains($0) }
            var lsalt = [Char]()
            let (lsaltARange, lsaltRange) = _saltify(&lsalt, lottery: lottery, alphabet: alphabet)

            for subHash in valueHashes {
                shuffle(&alphabet, salt: lsalt, saltRange: lsaltRange)
                ret.append(self._unhash(subHash, alphabet: alphabet))
                lsalt.replaceRange(lsaltARange, with: alphabet)
            }
        }
        
        return ret
    }
    
    private func _hash(inout hash: [Char], number: Int64, alphabet: [Char]) {
        let length = alphabet.count, index = hash.count
        var number = number
        repeat {
            hash.insert(alphabet[Int(number % Int64(length))], atIndex: index)
            number = number / Int64(length)
        } while number != 0
    }

    private func _unhash<U: CollectionType where U.Index == Int, U.Generator.Element == Char>(hash: U, alphabet: [Char]) -> Int64 {
        var value = 0.0
        
        let hashLength = hash.count
        if hashLength > 0 {
            let alphabetLength = alphabet.count
            
            for (index, token) in hash.enumerate() {
                if let token_index = alphabet.indexOf(token as Char) {
                    let mul = pow(Double(alphabetLength), Double(hashLength - index - 1))
                    value += Double(token_index) * mul
                }
            }
        }
        
        return Int64(trunc(value))
    }
    
    private func _saltify(inout salt: [Char], lottery: Char, alphabet: [Char]) -> (Range<Int>, Range<Int>) {
        salt.append(lottery)
        salt = salt + self.salt
        salt = salt + alphabet
        let lsaltARange = (self.salt.count + 1)..<salt.count
        let lsaltRange = 0..<alphabet.count
        return (lsaltARange, lsaltRange)
    }
   
}

// MARK: Internal functions

func contains<T: CollectionType where T.Generator.Element: Equatable>(a: T, e: T.Generator.Element) -> Bool {
    return a.indexOf(e) != nil
}

func transform<T: CollectionType where T.Generator.Element: Equatable>(a: T, _ b: T, cmpr: (inout [T.Generator.Element], T, T, T.Generator.Element ) -> Void ) -> [T.Generator.Element] {
    typealias U = T.Generator.Element
    var c = [U]()
    for i in a {
        cmpr(&c, a, b, i)
    }
    return c
}

func unique<T: CollectionType where T.Generator.Element: Equatable>(a: T) -> [T.Generator.Element] {
    return transform(a, a) { (c, a, b, e) in
        if !c.contains(e) {
            c.append(e)
        }
    }
}

func intersection<T: CollectionType where T.Generator.Element: Equatable>(a: T, _ b: T) -> [T.Generator.Element] {
    return transform(a, b) { (c, a, b, e) in
        if b.contains(e) {
            c.append(e)
        }
    }
}

func difference<T: CollectionType where T.Generator.Element: Equatable>(a: T, _ b: T) -> [T.Generator.Element] {
    return transform(a, b) { (c, a, b, e) in
        if !b.contains(e) {
            c.append(e)
        }
    }
}

func shuffle<T: MutableCollectionType, U: CollectionType where T.Index == Int, T.Generator.Element:UnsignedIntegerType, T.Generator.Element == U.Generator.Element, T.Index == U.Index>(inout source: T, salt: U) {
    return shuffle(&source, salt: salt, saltRange: 0..<salt.count)
}

func shuffle<T: MutableCollectionType, U:CollectionType where T.Index == Int, T.Generator.Element: UnsignedIntegerType, T.Generator.Element == U.Generator.Element, T.Index == U.Index>(inout source: T, salt: U, saltRange: Range<Int>) {
    let saltStartIndex = saltRange.startIndex
    let saltCount = (saltRange.endIndex - saltRange.startIndex)
    var sourceIndex = source.count - 1
    var v = 0
    var _p = 0
    while sourceIndex > 0 {
        v = v % saltCount
        let _i: Int = numericCast(salt[saltStartIndex + v])
        _p += _i
        let _j: Int = (_i + v + _p) % sourceIndex
        let tmp = source[sourceIndex]
        source[sourceIndex] = source[_j]
        source[_j] = tmp
        v += 1
        sourceIndex -= 1
    }
}
