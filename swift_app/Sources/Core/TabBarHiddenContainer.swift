import SwiftUI

/// 在宿主 `TabView` 中，push 出的子页默认仍会显示底部 TabBar；用该容器包一层目标页，
/// 通过 `.toolbar(.hidden, for: .tabBar)` 达到类似微信「仅根 Tab 显示底栏」的效果。
///
/// 进入子页时用短动画隐藏底栏；返回根页时不额外动画，避免与导航 pop、
/// 以及根页 `GeometryReader` 布局变化叠在一起产生「底栏顶出来」的感觉。
public struct TabBarHiddenContainer<Content: View>: View {
    @ViewBuilder public var content: () -> Content
    @State private var hideTabBar = false

    public init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    public var body: some View {
        #if os(iOS)
        content()
            .toolbar(hideTabBar ? .hidden : .automatic, for: .tabBar)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.28)) { hideTabBar = true }
            }
            .onDisappear {
                hideTabBar = false
            }
        #else
        content()
        #endif
    }
}
