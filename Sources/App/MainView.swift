import SwiftUI

/// 主界面：内核利用状态控制台（已移除卡密授权，启动即利用）
struct MainView: View {

    @State private var logs: [String] = []
    @State private var started = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 12) {
                header
                console
            }
            .padding()
        }
        .preferredColorScheme(.dark)
        .onAppear {
            guard !started else { return }
            started = true
            runExploit()
        }
    }

    private var header: some View {
        HStack {
            Text("DeltaTroll")
                .font(.system(size: 26, weight: .black, design: .monospaced))
                .foregroundColor(.green)
            Spacer()
            Circle()
                .fill(logs.contains("内核读写获取成功") ? Color.green : Color.red)
                .frame(width: 10, height: 10)
        }
    }

    private var console: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(logs.indices, id: \.self) { i in
                        Text(logs[i])
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(logs[i].contains("失败") || logs[i].contains("错误") ? .red : .green)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(i)
                    }
                }
                .padding(6)
                .background(Color(white: 0.08))
                .cornerRadius(8)
            }
            .onChange(of: logs.count) { _ in
                proxy.scrollTo(logs.count - 1, anchor: .bottom)
            }
        }
    }

    private func log(_ s: String) {
        logs.append(s)
    }

    private func runExploit() {
        log("开始内核利用")
        ExploitController.shared().run { line, done in
            DispatchQueue.main.async {
                log(line ?? "")
                if done {
                    log("内核读写已就绪")
                    DispatchQueue.global().async {
                        var err: NSString?
                        let ok = DFClient.shared().attachWithError(&err)
                        DispatchQueue.main.async {
                            if ok {
                                log("已附加 Delta Force")
                                OverlayBridge.shared().showOverlay()
                            } else {
                                log("未找到游戏进程，进入游戏后重试")
                            }
                        }
                    }
                }
            }
        }
    }
}
