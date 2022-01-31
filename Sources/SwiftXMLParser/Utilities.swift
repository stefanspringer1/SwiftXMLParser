//
//  Utilities.swift
//
//  Created 2021 by Stefan Springer, https://stefanspringer.com
//  License: Apache License 2.0

import Foundation

struct Stack<Element> {
    var elements = [Element]()
    mutating func push(_ item: Element) {
        elements.append(item)
    }
    mutating func change(_ item: Element) {
        _ = pop()
        elements.append(item)
    }
    mutating func pop() -> Element? {
        if elements.isEmpty {
            return nil
        }
        else {
            return elements.removeLast()
        }
    }
    func peek() -> Element? {
        return elements.last
    }
    func peekAll() -> [Element] {
        return elements
    }
}

public class WeaklyListed<T: AnyObject> {
    var next: WeaklyListed<T>? = nil
    
    weak var element: T?
    
    init(_ element: T) {
        self.element = element
    }
}
