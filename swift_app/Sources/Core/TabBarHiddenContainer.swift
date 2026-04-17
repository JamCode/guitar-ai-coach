import SwiftUI

/// 在宿主 `TabView` 中，push 出的子页默认仍会显示底部 TabBar；用该容器包一层目标页，
/// 通过 `.toolbar(.hidden, for: .tabBar)` 达到类似微信「仅根 Tab 显示底栏」的效果。
///
/// 出现/消失时用短动画切换，减轻返回根页时底栏突然弹出的突兀感。
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
                withAnimation(.easeInOut(duration: 0.28)) { hideTabBar = false }
            }
        #else
        content()
        #endif
    }
}
