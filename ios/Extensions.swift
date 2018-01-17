//
//  Extensions.swift
//  Frimousse
//
//  Created by Thibaut NOAH on 27/11/2017.
//  Copyright © 2017 mvpstars. All rights reserved.
//

import Foundation

extension Date {
    var ticks: UInt64 {
        return UInt64((self.timeIntervalSince1970 + 62_135_596_800) * 10_000_000)
    }
}
