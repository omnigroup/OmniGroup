// Copyright 2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

import SwiftUI

internal struct OUIDocumentBrowserWelcome: View {
    internal static var bundle: Bundle?
    @EnvironmentObject var welcomeEnvironment: WelcomeEnvironment

    internal final class WelcomePage: ObservableObject {
        var wantsSplash = false
        var localizedTitleText = ""
        var wantsIllustration = false
        var localizedDescriptionText = ""
        var learnMoreBlock: (() -> Void)?
    }

    internal final class WelcomeEnvironment: ObservableObject {
        @Published var currentPage: WelcomePage
        var appName: String
        var localizedLearnMoreText: String = ""
        var localizedContinueText: String = ""
        var allPages: [WelcomePage]
        var closeBlock: (() -> Void)?
        var currentPageIndex: Int = 0

        init(appName: String, pages: [WelcomePage]) {
            self.appName = appName
            allPages = pages
            currentPage = allPages.first!
        }

        func continueAction() {
            currentPageIndex += 1
            if currentPageIndex < allPages.count {
                currentPage = allPages[currentPageIndex]
            } else if let actionBlock = closeBlock {
                actionBlock()
            }
        }
    }

    fileprivate let verticalMargin: CGFloat = 20.0
    fileprivate func splashHeight(for size: CGSize) -> CGFloat {
        guard welcomeEnvironment.currentPage.wantsSplash else { return 0.0 }

        let totalHeight = size.height
        let minimumBodyHeight: CGFloat = 400.0
        let availableHeight = totalHeight - minimumBodyHeight

        let minSplashPercentage: CGFloat = 0.25
        let minUsefulHeight = minSplashPercentage * totalHeight
        if availableHeight < minUsefulHeight { return 0.0 }

        let goldenRatio = 1.61803398874989484820
        let maxSplashPercentage: CGFloat = CGFloat(1.0 - (1.0 / goldenRatio))
        let maxUsefulHeight = maxSplashPercentage * totalHeight
        if availableHeight > maxUsefulHeight { return maxUsefulHeight }

        return availableHeight
    }

    fileprivate func bodyHeight(for size: CGSize) -> CGFloat {
        return size.height - splashHeight(for: size)
    }

    fileprivate func shouldShowSplash(for size: CGSize) -> Bool {
        let splashHeight = self.splashHeight(for: size)
        return splashHeight > 0.0
    }

    var body: some View {
        GeometryReader { geometry in
            VStack {
                if self.shouldShowSplash(for: geometry.size) {
                    SplashImage()
                        .scaleEffect(SplashImage.scale(for: geometry.size))
                        .frame(maxHeight: self.splashHeight(for: geometry.size), alignment: .center)
                        .clipped()
                        .edgesIgnoringSafeArea(.top)
                }
                VStack {
                    ScrollingPageText(page: self.welcomeEnvironment.currentPage, topMargin: self.verticalMargin)
                    Spacer(minLength: 0).layoutPriority(-100)

                    VStack {
                        LearnMoreLink()
                        ContinueButton()
                        Spacer().frame(height: self.verticalMargin)
                    }
                    .padding(.horizontal, 64)
                    .fixedSize(horizontal: false, vertical: false)
                    .layoutPriority(1)
                }
                .frame(width: min(geometry.size.width, 600.0),
                       height: self.bodyHeight(for: geometry.size),
                       alignment: .bottom)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    fileprivate struct SplashImage: View {
        static let uiImage = UIImage(named: "DocumentBrowserWelcomeSplash", in: bundle, compatibleWith: nil)!
        static func scale(for geometrySize: CGSize) -> CGFloat {
            return 3.5 * geometrySize.width / uiImage.size.width
        }

        var body: some View {
            ZStack(alignment: .center) {
                Image(uiImage: Self.uiImage)
            }
            .clipped()
        }
    }

    fileprivate struct ScrollingPageText: View {
        var page: WelcomePage
        static let gradientStart = Color(.systemBackground).opacity(0.0)
        static let gradientEnd = Color(.systemBackground)
        var topMargin: CGFloat
        var body: some View {
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack {
                        Spacer(minLength: topMargin).position(x: 0.0, y: 0.0)
                        ZStack(alignment: .top) {
                            PageText(page: page)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }.overlay(
                    Rectangle()
                        .fill(LinearGradient(
                            gradient: .init(colors: [Self.gradientStart, Self.gradientEnd]),
                            startPoint: .init(x: 0.5, y: 0),
                            endPoint: .init(x: 0.5, y: 1.0)
                        ))
                        .frame(maxHeight: topMargin * 2),

                    alignment: .bottom
                )
            }
        }
    }

    fileprivate struct PageText: View {
        var page: WelcomePage
        var body: some View {
            VStack {
                TitleText(text: page.localizedTitleText)
                Illustration(wantsIllustration: page.wantsIllustration)
                DescriptionText(text: page.localizedDescriptionText)
            }.padding(.horizontal)
        }
    }

    fileprivate struct TitleText: View {
        var text: String

        var body: some View {
            Text(text)
                .bold()
                .font(.title)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    fileprivate struct Illustration: View {
        static let uiImage = UIImage(named: "DocumentBrowserWelcomeIllustration", in: bundle, compatibleWith: nil)!
        var wantsIllustration = false
        var body: some View {
            VStack {
                if (wantsIllustration) {
                    Image(uiImage: Self.uiImage)
                }
            }
        }
    }

    fileprivate struct DescriptionText: View {
        var text: String

        var body: some View {
            Text(text)
                .font(.headline)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 12)
        }
    }

    fileprivate struct LearnMoreLink: View {
        @EnvironmentObject var welcomeEnvironment: WelcomeEnvironment
        var body: some View {
            Button(action: {
                if let actionBlock = self.welcomeEnvironment.currentPage.learnMoreBlock {
                    actionBlock()
                }
            }) {
                Text(welcomeEnvironment.localizedLearnMoreText)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(height: 32.0)
            }
        }
    }

    fileprivate struct ContinueButton: View {
        @EnvironmentObject var welcomeEnvironment: WelcomeEnvironment
        var body: some View {
            DefaultActionButton(title: welcomeEnvironment.localizedContinueText) {
                self.welcomeEnvironment.continueAction()
            }
        }
    }

   fileprivate struct DefaultActionButton: View {
        var title: String
        var action: () -> Void

        var body: some View {
            GeometryReader { geometry in
                Button(action: self.action) {
                    Text(self.title)
                        .foregroundColor(.white)
                        .bold()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }
                .background(RoundedRectangle(cornerRadius: 6.0)
                .foregroundColor(.accentColor))
            }
            .frame(height: 32.0)
        }
    }
}

#if DEBUG

extension OUIDocumentBrowserWelcome {
    static var previewEnvironment: WelcomeEnvironment {
        let page1 = WelcomePage()
        page1.wantsSplash = true
        page1.localizedTitleText = "New in iOS 13:\nFull Adoption of Apple's Document Browser"
        page1.localizedDescriptionText = "We've retired our custom document browser in favor of using Apple's built-in browser, making it easier than ever for you to choose where you want to keep your documents."
        page1.learnMoreBlock = {
            print("Action: Page 1 Learn More")
        }

        let page2 = WelcomePage()
        page2.wantsIllustration = true
        page2.localizedTitleText = "OmniPresence Documents"
        page2.localizedDescriptionText = "Your OmniPresence documents will only be visible in the new browser when they’ve been downloaded to this device.\n\nOmniPresence does not download larger synced files automatically. You can manually download larger files to this device now, or access the download manager later from the OmniPresence icon in the toolbar."
        page2.learnMoreBlock = {
            print("Action: Page 2 Learn More")
        }

        let environment = WelcomeEnvironment(appName: "OmniOutliner", pages: [page1, page2])
        environment.localizedLearnMoreText = "Learn More"
        environment.localizedContinueText = "Continue"
        environment.closeBlock = {
            print("Action: Close")
        }
        return environment
    }
}

struct OUIDocumentBrowserWelcome_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            OUIDocumentBrowserWelcome()
                .previewLayout(.fixed(width: 712, height: 688))
            OUIDocumentBrowserWelcome()
                .previewLayout(.fixed(width: 808, height: 393))
            OUIDocumentBrowserWelcome()
                .previewDevice("iPhone SE")
            OUIDocumentBrowserWelcome()
                .previewDevice("iPhone Xs")
            OUIDocumentBrowserWelcome()
                .previewDevice("iPad Pro (12.9-inch) (3rd generation)")
        }
        .environmentObject(OUIDocumentBrowserWelcome.previewEnvironment)
    }
}

#endif
