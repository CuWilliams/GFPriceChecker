//
//  OnboardingViewModelTests.swift
//  GFPriceCheckerTests
//
//  Created by Claude Code on 2026-11-01.
//

import Testing
@testable import GFPriceChecker

/// The onboarding sheet's paging, which `OnboardingView`'s Back and Next
/// buttons and the demo's `onboarding` script both drive.
@MainActor
@Suite("Onboarding view model")
struct OnboardingViewModelTests {

    @Test("Starts on the welcome page")
    func startsOnWelcome() {
        let viewModel = OnboardingViewModel()

        #expect(viewModel.page == .welcome)
        #expect(viewModel.isFirstPage)
        #expect(viewModel.isLastPage == false)
    }

    @Test("Next walks every page in order, and stays on the last")
    func nextWalksThePages() {
        let viewModel = OnboardingViewModel()
        var visited = [viewModel.page]

        for _ in 1..<OnboardingViewModel.Page.allCases.count {
            viewModel.next()
            visited.append(viewModel.page)
        }

        #expect(visited == [.welcome, .howItWorks, .smartScanning, .camera, .ready])
        #expect(viewModel.isLastPage)

        viewModel.next()
        #expect(viewModel.page == .ready)
    }

    @Test("Back steps to the previous page, and stays on the first")
    func backStepsBack() {
        let viewModel = OnboardingViewModel()
        viewModel.page = .camera

        viewModel.back()
        #expect(viewModel.page == .smartScanning)

        viewModel.page = .welcome
        viewModel.back()
        #expect(viewModel.page == .welcome)
    }
}
