//
//  MixtapeGridTests.swift
//  RadioTests
//
//  `MixtapeGrid` is the single source of truth for the panel's mixtape section
//  geometry, shared by `MixtapeGridView` and `AppDelegate.panelSize`. If the
//  column rules or tile maths move here, the hand-computed panel height moves too.
//

import Foundation
import Testing
@testable import Radio

@Suite("MixtapeGrid")
struct MixtapeGridTests {

    @Test func columnRules() {
        // 3 per row for multiples-ish of three (3/6/9), 5 per row for 5/10, else 4.
        #expect(MixtapeGrid.columns(for: 3) == 3)
        #expect(MixtapeGrid.columns(for: 6) == 3)
        #expect(MixtapeGrid.columns(for: 9) == 3)
        #expect(MixtapeGrid.columns(for: 5) == 5)
        #expect(MixtapeGrid.columns(for: 10) == 5)
        for n in [1, 2, 4, 7, 8, 11, 12, 16] {
            #expect(MixtapeGrid.columns(for: n) == 4, "count \(n) should be 4 per row")
        }
    }

    @Test func rowCount() {
        #expect(MixtapeGrid.rows(count: 0, columns: 4) == 0)
        #expect(MixtapeGrid.rows(count: 4, columns: 4) == 1)
        #expect(MixtapeGrid.rows(count: 6, columns: 3) == 2)
        #expect(MixtapeGrid.rows(count: 7, columns: 4) == 2)
        #expect(MixtapeGrid.rows(count: 10, columns: 5) == 2)
    }

    @Test func tileEdgeIsPositiveAndShrinksWithMoreColumns() {
        let three = MixtapeGrid.tileEdge(columns: 3)
        let four = MixtapeGrid.tileEdge(columns: 4)
        let five = MixtapeGrid.tileEdge(columns: 5)
        #expect(five > 0)
        #expect(three > four)
        #expect(four > five)
    }

    @Test func emptySectionHasNoHeight() {
        #expect(MixtapeGrid.sectionHeight(count: 0) == 0)
    }

    @Test func sectionHeightGrowsWithASecondRow() {
        let oneRow = MixtapeGrid.sectionHeight(count: 4)   // 4 per row -> 1 row
        let twoRows = MixtapeGrid.sectionHeight(count: 8)  // 4 per row -> 2 rows
        #expect(oneRow > 0)
        #expect(twoRows > oneRow)
    }
}
