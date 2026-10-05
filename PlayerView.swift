import AppKit
import SwiftUI
import CoreAudio
import AudioToolbox
import AVFoundation
import ServiceManagement

struct PlayerView: View {
    @ObservedObject var player: Player
    @State private var seeking = false
    @State private var seekValue = 0.0
    private func time(_ seconds: Double) -> String {
        let value = max(0, Int(seconds)); return String(format: "%d:%02d", value / 60, value % 60)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .center, spacing: 16) {
                Group {
                    if let artwork = player.artwork { Image(nsImage: artwork).resizable().scaledToFill() }
                    else {
                        ZStack {
                            Color.primary.opacity(0.08)
                            Image(systemName: "music.note")
                                .font(.title)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(width: 90, height: 90).clipped().clipShape(RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 5) {
                    Text(player.title).font(.system(size: 18, weight: .semibold)).lineLimit(1)
                    Text(player.artist).font(.system(size: 14)).foregroundStyle(.secondary).lineLimit(1)
                    HStack(spacing: 20) {
                        Button { player.back() } label: { Image(systemName: "backward.fill") }
                        Button { player.toggle() } label: { Image(systemName: player.playing ? "pause.fill" : "play.fill").font(.system(size: 24)) }
                        Button { player.next() } label: { Image(systemName: "forward.fill") }
                    }
                    .buttonStyle(.plain).font(.system(size: 18)).padding(.top, 10)
                }
                Spacer(minLength: 0)
            }
            VStack(spacing: 3) {
                Slider(value: Binding(get: { seeking ? seekValue : player.position }, set: { seekValue = $0; seeking = true }), in: 0...max(1, player.duration), onEditingChanged: { editing in
                    if !editing { player.seek(seekValue); seeking = false }
                }).tint(.blue)
                HStack { Text(time(player.position)); Spacer(); Text("−" + time(player.duration - player.position)) }
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
            }
            Divider()
            EqualizerView(player: player)
            HStack {
                Text(player.status).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .padding(20).frame(width: 430)
    }
}
