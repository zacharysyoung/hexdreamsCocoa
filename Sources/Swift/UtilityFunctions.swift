//
//  UtilityFunctions.swift
//  hexdreamsCocoa
//
//  Created by Kenny Leung on 7/6/18.
//  Copyright © 2018 hexdreams. All rights reserved.
//

// https://forums.swift.org/t/pre-draft-nil-coalescing-and-errors/2070/4
public func ??<T>(
    optional:T?,
    defaultValue:()throws->T
    ) rethrows
    -> T
{
    switch optional {
    case .some(let wrapped):
        return wrapped
    case .none:
        return try defaultValue()
    }
}

// It's only OK to call this with variables, since NSLocalizedString is scanned by a tool in order to generate string tables.
public func HXLocalize(_ unlocalized:String?, plural:Bool = false) -> String {
    guard var str = unlocalized else {
        fatalError("Unlocalized string is nil")
    }
    if plural {
        str += ".plural"
    }
    return NSLocalizedString(str, comment:"")
}
