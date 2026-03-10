//
//  Item.swift
//  Typetex
//
//  Created by Jonas Gunklach on 04.05.26.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
