# SwiftXMLParser

---

⚠️ **NOTE:**

This package is _deprecated;_ use the following, currently maintained package instead:

https://github.com/swiftxml/SwiftXMLParser

---

## About This Library

This is a non-validating parser for XML files encoded in UTF-8.

This library is published under the Apache License 2.0, please feel free to use it and change it. Any remark or suggestion or pull requests are welcome, see also my contact information on [my website](https://stefanspringer.com).

## Important Notes

- This library comes without any warranty.
- This is only a first version of the library, it may have some serious bugs at the moment or change significantly in the near future.
- The active repository will move to a new place. The new place will then be noted here.

## Main Aspects of This Parser

Entities that are not understood as external entities according to the internal subset of the document (they are then called "internal" entities here) can be replaced by the client. Internal entities in attribute values have to be replaced by the client, internal attributes in text might remain. This entity handling can be added by the client in form of a trailing closure to the parse call, receiving the entity name and the optional names of the element and the attribute, if the entity is from an attribute value.

Besides entity handling, the client uses the parser by an instance of type "XMLEventHandler" defined in the (XMLInterfaces)[https://github.com/stefanspringer1/XMLInterfaces] repository.

## Some Limitations of This Parser

- It only parses XML docmuments encoded in UTF-8.
- It does not recognize XML namespaces. (Namespaces should be processed by a consumer of the parse events.)
- It understands document type declaration and entity declarations, but does not do any validation against a DTD (or any other scheme). Such a validation should be done by a consumer of the parse events, and such a consumer could then also be applied to an aleady built XML tree. Parsing and validation do not belong together.
- The only external files that are read by the parser are external parsed entities (if configurated).
- It parses element declarations ("\<!ELEMENT ... >") and attribute list declarations ("\<!ATTLIST ... >") only in the form of its definition as text, it does not uses them for validation, and no enttites within them are replaced.

## Documentation

More documentation will be added (if the active repository is not moved yet, see abobe), either in this README file or as code comments.

## Facilities for testing

Fopr testing of the parser, one might want to use one of the following functions. They print the parser event together with extractions according to the binary and text positions that are reported:

```Swift
func xParseTest(forData: Data, writer: XTestWriter, fullDebugOutput: Bool)
```

```Swift
func xParseTest(forPath: String, writer: XTestWriter, fullDebugOutput: Bool) throws
```

```Swift
func xParseTest(forText: String, writer: XTestWriter, fullDebugOutput: Bool)
```

```Swift
func xParseTest(forURL: URL, writer: XTestWriter, fullDebugOutput: Bool) throws
```

Example:

```Swift
let source = """
<a>Hi</a>
"""

xParseTest(forText: source, fullDebugOutput: false)
```

Output:

```text
document started
start of element: name "a", no attributes; 1:1 - 1:3 (0..<3 in data)
  binary excerpt: {<a>}
  line excerpt:   {<a>}
text: "Hi", whitespace indicator NOT_WHITESPACE; 1:4 - 1:5 (3..<5 in data)
  binary excerpt: {Hi}
  line excerpt:   {Hi}
end of element: name "a"; 1:6 - 1:9 (5..<9 in data)
  binary excerpt: {</a>}
  line excerpt:   {</a>}
document ended
```

If you set `fullDebugOutput` to true, the characters are printed together with the internal states of the parser:

```text
document started
@ 1:1 (#0 in data): "<" in TEXT in TEXT (whitespace was: true)
@ 1:2 (#1 in data): "a" in JUST_STARTED_WITH_LESS_THAN_SIGN in TEXT (whitespace was: true)
@ 1:3 (#2 in data): ">" in START_OR_EMPTY_TAG in TEXT (whitespace was: true)
start of element: name "a", no attributes; 1:1 - 1:3 (0..<3 in data)
  binary excerpt: {<a>}
  line excerpt:   {<a>}
@ 1:4 (#3 in data): "H" in TEXT in TEXT (whitespace was: true)
@ 1:5 (#4 in data): "i" in TEXT in TEXT (whitespace was: false)
@ 1:6 (#5 in data): "<" in TEXT in TEXT (whitespace was: false)
text: "Hi", whitespace indicator NOT_WHITESPACE; 1:4 - 1:5 (3..<5 in data)
  binary excerpt: {Hi}
  line excerpt:   {Hi}
@ 1:7 (#6 in data): "/" in JUST_STARTED_WITH_LESS_THAN_SIGN in TEXT (whitespace was: true)
@ 1:8 (#7 in data): "a" in END_TAG in TEXT (whitespace was: true)
@ 1:9 (#8 in data): ">" in END_TAG in TEXT (whitespace was: true)
end of element: name "a"; 1:6 - 1:9 (5..<9 in data)
  binary excerpt: {</a>}
  line excerpt:   {</a>}
document ended
```

If you want to adjust this testing e.g. to write the debug output to somewhere else, then look at the implementation of `xParseTest(forData:writer:fullDebugOutput:)`.
