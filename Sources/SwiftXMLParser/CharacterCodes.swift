//===--- CharacterCodes.swift ---------------------------------------------===//
//
// This source file is part of the SwiftXML.org open source project
//
// Copyright (c) 2021-2023 Stefan Springer (https://stefanspringer.com)
// and the SwiftXML project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
//===----------------------------------------------------------------------===//

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

let U_BOM_1: Data.Element = 0xEF
let U_BOM_2: Data.Element = 0xBB
let U_BOM_3: Data.Element = 0xBF

let U_BOM: UnicodeCodePoint = 0xFEFF

typealias UnicodeCodePoint = UInt32

let U_MAX_ASCII: UnicodeCodePoint = 0x7E

// XML whitespace:
let U_CHARACTER_TABULATION: UnicodeCodePoint = 0x9
let U_LINE_FEED: UnicodeCodePoint = 0xA
let U_CARRIAGE_RETURN: UnicodeCodePoint = 0xD
let U_SPACE: UnicodeCodePoint = 0x20

// XML whitespaces as characters:
let C_CHARACTER_TABULATION = Character(UnicodeScalar(U_CHARACTER_TABULATION)!)
let C_LINE_FEED = Character(UnicodeScalar(U_LINE_FEED)!)
let C_CARRIAGE_RETURN = Character(UnicodeScalar(U_CARRIAGE_RETURN)!)
let C_SPACE = Character(UnicodeScalar(U_SPACE)!)

// other characters:
let U_EXCLAMATION_MARK: UnicodeCodePoint = 0x21
let U_QUOTATION_MARK: UnicodeCodePoint = 0x22
let U_NUMBER_SIGN: UnicodeCodePoint = 0x23
let U_PERCENT_SIGN: UnicodeCodePoint = 0x25
let U_AMPERSAND: UnicodeCodePoint = 0x26
let U_APOSTROPHE: UnicodeCodePoint = 0x27
let U_LEFT_PARENTHESIS: UnicodeCodePoint = 0x28
let U_COMMA: UnicodeCodePoint = 0x2C
let U_HYPHEN_MINUS: UnicodeCodePoint = 0x2D
let U_FULL_STOP: UnicodeCodePoint = 0x2E
let U_SOLIDUS: UnicodeCodePoint = 0x2F
let U_DIGIT_ZERO: UnicodeCodePoint = 0x30
let U_DIGIT_NINE: UnicodeCodePoint = 0x39
let U_COLON: UnicodeCodePoint = 0x3A
let U_SEMICOLON: UnicodeCodePoint = 0x3B
let U_LESS_THAN_SIGN: UnicodeCodePoint = 0x3C
let U_EQUALS_SIGN: UnicodeCodePoint = 0x3D
let U_GREATER_THAN_SIGN: UnicodeCodePoint = 0x3E
let U_QUESTION_MARK: UnicodeCodePoint = 0x3F
let U_LATIN_CAPITAL_LETTER_A: UnicodeCodePoint = 0x41
let U_LATIN_CAPITAL_LETTER_C: UnicodeCodePoint = 0x43
let U_LATIN_CAPITAL_LETTER_D: UnicodeCodePoint = 0x44
let U_LATIN_CAPITAL_LETTER_E: UnicodeCodePoint = 0x45
let U_LATIN_CAPITAL_LETTER_I: UnicodeCodePoint = 0x49
let U_LATIN_CAPITAL_LETTER_L: UnicodeCodePoint = 0x4C
let U_LATIN_CAPITAL_LETTER_M: UnicodeCodePoint = 0x4D
let U_LATIN_CAPITAL_LETTER_N: UnicodeCodePoint = 0x4E
let U_LATIN_CAPITAL_LETTER_O: UnicodeCodePoint = 0x4F
let U_LATIN_CAPITAL_LETTER_P: UnicodeCodePoint = 0x50
let U_LATIN_CAPITAL_LETTER_S: UnicodeCodePoint = 0x53
let U_LATIN_CAPITAL_LETTER_T: UnicodeCodePoint = 0x54
let U_LATIN_CAPITAL_LETTER_Y: UnicodeCodePoint = 0x59
let U_LATIN_CAPITAL_LETTER_Z: UnicodeCodePoint = 0x5A
let U_LEFT_SQUARE_BRACKET: UnicodeCodePoint = 0x5B
let U_REVERSE_SOLIDUS: UnicodeCodePoint = 0x5C
let U_RIGHT_SQUARE_BRACKET: UnicodeCodePoint = 0x5D
let U_LOW_LINE: UnicodeCodePoint = 0x5F
let U_LATIN_SMALL_LETTER_A: UnicodeCodePoint = 0x61
let U_LATIN_SMALL_LETTER_L: UnicodeCodePoint = 0x6C
let U_LATIN_SMALL_LETTER_M: UnicodeCodePoint = 0x6D
let U_LATIN_SMALL_LETTER_X: UnicodeCodePoint = 0x78
let U_LATIN_SMALL_LETTER_Z: UnicodeCodePoint = 0x7A
let U_LEFT_CURLY_BRACKET: UnicodeCodePoint = 0x7B
let U_RIGHT_CURLY_BRACKET: UnicodeCodePoint = 0x7D
