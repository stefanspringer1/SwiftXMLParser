# SwiftXMLParser

## About This Library

This is a non-validating parser for XML files encoded in UTF-8.

This library is published under the Apache License 2.0, please feel free to use it and change it. Any remark or suggestion or pull requests are welcome, see also my contact information on [my website](https://stefanspringer.com).

## Important Notes

- This library comes without any warranty.
- This is only a first version of the library, it may have some serious bugs at the moment or change significantly in the near future.
- The active repository will move to a new place. The new place will then be noted here.

## Main Aspects of This Parser

Entities that are not understood as external entities according to the internal subset of the document (they are then called "internal" entities here)can be replaced by the client. Internal entities in attribute values have to be replaced by the client, internal attributes in text might remain. This entity handling can be added by the client in form of a trailing closure to the parse call, receiving the entity name and the optional names of the element and the attribute, if the entity is from an attribute value.

Besides entity handling, the client uses the parser by an instance of type "XMLEventHandler" defined in the (XMLInterfaces)[https://github.com/stefanspringer1/XMLInterfaces] repository.

## Some Limitations of This Parser

- It only parses XML docmuments encoded in UTF-8.
- it understands document type declaration and entity declarations, but does not do any validation against a DTD (or any other scheme) and does not read any external files.
- It parses element declarations ("<!ELEMENT ... >") and attribute list declarations ("<!ATTLIST ... >") only in the form of its definition as text, it does not uses them for valöidation, and no enttites within them are replaced.

## Documentation

More documentation will be added (if the active repository is not moved yet, see abobe), either in this README file or as code comments.
