import SwiftUI
import Core

struct CommonChordProgressionsView: View {
    @State private var selectedGenre: ProgressionGenre = .all
    @State private var searchText = ""

    private var filteredProgressions: [CommonChordProgression] {
        CommonChordProgression.library.filter { item in
            let matchesGenre = selectedGenre == .all || item.genre == selectedGenre
            guard matchesGenre else { return false }

            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return true }

            let haystack = [
                item.title,
                item.roman,
                item.practiceKey,
                item.genre.title,
                item.feel,
                item.practiceTip,
                item.chords.joined(separator: " "),
                item.zhSongExamples.map(\.displayText).joined(separator: " "),
                item.enSongExamples.map(\.displayText).joined(separator: " "),
            ].joined(separator: " ").lowercased()
            return haystack.contains(query.lowercased())
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                introCard
                genreSelector

                ForEach(filteredProgressions) { item in
                    ProgressionCard(progression: item)
                }

                if filteredProgressions.isEmpty {
                    ContentUnavailableView(
                        "没有匹配的和弦进行",
                        systemImage: "magnifyingglass",
                        description: Text("换一个风格或搜索关键词试试。")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                }
            }
            .padding(SwiftAppTheme.pagePadding)
        }
        .navigationTitle("常用和弦进行")
        .searchable(text: $searchText, prompt: "搜索风格、歌曲或级数")
        .appPageBackground()
    }

    private var introCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("按真实歌曲练习", systemImage: "music.note")
                .font(.headline)
                .foregroundStyle(SwiftAppTheme.text)
            Text("每条都给出常见级数、一个适合吉他的练习调，以及可参考的歌曲。先按推荐调顺手弹熟，再用变调夹或移调练到目标调。")
                .font(.subheadline)
                .foregroundStyle(SwiftAppTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .appCard()
    }

    private var genreSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ProgressionGenre.allCases) { genre in
                    Button {
                        selectedGenre = genre
                    } label: {
                        Label(genre.title, systemImage: genre.icon)
                            .font(.subheadline.weight(.semibold))
                            .labelStyle(.titleAndIcon)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(selectedGenre == genre ? SwiftAppTheme.brandSoft : SwiftAppTheme.surface)
                            .foregroundStyle(selectedGenre == genre ? SwiftAppTheme.brand : SwiftAppTheme.text)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(selectedGenre == genre ? SwiftAppTheme.brand.opacity(0.35) : SwiftAppTheme.line, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct ProgressionCard: View {
    let progression: CommonChordProgression

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: progression.genre.icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(SwiftAppTheme.brand)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 4) {
                    Text(progression.title)
                        .font(.headline)
                        .foregroundStyle(SwiftAppTheme.text)
                    Text("\(progression.genre.title) · \(progression.feel)")
                        .font(.caption)
                        .foregroundStyle(SwiftAppTheme.muted)
                }

                Spacer(minLength: 8)

                Text(progression.roman)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SwiftAppTheme.brand)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(SwiftAppTheme.brandSoft)
                    .clipShape(Capsule())
            }

            chordRow

            VStack(alignment: .leading, spacing: 6) {
                Label("练习调：\(progression.practiceKey)", systemImage: "guitars")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SwiftAppTheme.text)
                Text(progression.practiceTip)
                    .font(.subheadline)
                    .foregroundStyle(SwiftAppTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("可参考歌曲")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SwiftAppTheme.text)
                ForEach(progression.songExamples) { song in
                    Text("• \(song.displayText)")
                        .font(.subheadline)
                        .foregroundStyle(SwiftAppTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .appCard()
    }

    private var chordRow: some View {
        FlowLayout(spacing: 8, runSpacing: 8) {
            ForEach(Array(progression.chords.enumerated()), id: \.offset) { index, chord in
                HStack(spacing: 8) {
                    chordChip(chord)

                    if index < progression.chords.count - 1 {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(SwiftAppTheme.muted)
                    }
                }
            }
        }
    }

    private func chordChip(_ chord: String) -> some View {
        Text(chord)
            .font(.title3.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(SwiftAppTheme.text)
            .frame(minWidth: 54)
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(SwiftAppTheme.surfaceSoft)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(SwiftAppTheme.line, lineWidth: 1)
            )
    }
}

private enum ProgressionGenre: String, CaseIterable, Identifiable {
    case all
    case pop
    case rock
    case folkCountry
    case blues
    case jazzSoul
    case latin

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "全部"
        case .pop: return "流行"
        case .rock: return "摇滚"
        case .folkCountry: return "民谣/乡村"
        case .blues: return "布鲁斯"
        case .jazzSoul: return "爵士/R&B"
        case .latin: return "拉丁/弗拉门戈"
        }
    }

    var icon: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .pop: return "sparkles"
        case .rock: return "bolt.fill"
        case .folkCountry: return "leaf"
        case .blues: return "guitars"
        case .jazzSoul: return "pianokeys"
        case .latin: return "flame"
        }
    }
}

private struct SongExample: Identifiable {
    let id = UUID()
    let title: String
    let artist: String

    var displayText: String {
        "\(title) - \(artist)"
    }
}

private struct CommonChordProgression: Identifiable {
    let id = UUID()
    let title: String
    let genre: ProgressionGenre
    let roman: String
    let practiceKey: String
    let chords: [String]
    let feel: String
    let practiceTip: String
    let zhSongExamples: [SongExample]
    let enSongExamples: [SongExample]

    var songExamples: [SongExample] {
        Locale.guitarCoachPrefersChinese ? zhSongExamples : enSongExamples
    }
}

private extension Locale {
    static var guitarCoachPrefersChinese: Bool {
        guard let language = Locale.preferredLanguages.first else { return false }
        return language.hasPrefix("zh")
    }
}

private extension CommonChordProgression {
    static let library: [CommonChordProgression] = [
        CommonChordProgression(
            title: "Axis 流行万能进行",
            genre: .pop,
            roman: "I-V-vi-IV",
            practiceKey: "C 大调",
            chords: ["C", "G", "Am", "F"],
            feel: "稳定、明亮、适合分解和扫弦",
            practiceTip: "先用每小节一个和弦练 4/4 下扫，再换成分解节奏。F 可先用 Fmaj7 或小横按过渡。",
            zhSongExamples: [
                SongExample(title: "平凡之路", artist: "朴树"),
                SongExample(title: "小幸运", artist: "田馥甄"),
                SongExample(title: "倔强", artist: "五月天"),
            ],
            enSongExamples: [
                SongExample(title: "With or Without You", artist: "U2"),
                SongExample(title: "Let It Be", artist: "The Beatles"),
                SongExample(title: "I'm Yours", artist: "Jason Mraz"),
            ]
        ),
        CommonChordProgression(
            title: "小调流行副歌进行",
            genre: .pop,
            roman: "vi-IV-I-V",
            practiceKey: "G 大调 / E 小调",
            chords: ["Em", "C", "G", "D"],
            feel: "情绪化、现代流行常用",
            practiceTip: "把重音放在每小节第 2、4 拍，练习从 Em 到 C 的手型最短移动。",
            zhSongExamples: [
                SongExample(title: "你不是真正的快乐", artist: "五月天"),
                SongExample(title: "突然好想你", artist: "五月天"),
                SongExample(title: "安静", artist: "周杰伦"),
            ],
            enSongExamples: [
                SongExample(title: "Zombie", artist: "The Cranberries"),
                SongExample(title: "Numb", artist: "Linkin Park"),
                SongExample(title: "Apologize", artist: "OneRepublic"),
            ]
        ),
        CommonChordProgression(
            title: "经典 Doo-wop 循环",
            genre: .jazzSoul,
            roman: "I-vi-IV-V",
            practiceKey: "C 大调",
            chords: ["C", "Am", "F", "G"],
            feel: "复古、圆润、适合慢速摆动",
            practiceTip: "每个和弦先弹根音再扫弦，听低音线 C-A-F-G 的走向。",
            zhSongExamples: [
                SongExample(title: "月亮代表我的心", artist: "邓丽君"),
                SongExample(title: "恰似你的温柔", artist: "蔡琴"),
                SongExample(title: "爱你在心口难开", artist: "凤飞飞"),
            ],
            enSongExamples: [
                SongExample(title: "Stand By Me", artist: "Ben E. King"),
                SongExample(title: "Earth Angel", artist: "The Penguins"),
                SongExample(title: "Blue Moon", artist: "The Marcels"),
            ]
        ),
        CommonChordProgression(
            title: "Pachelbel 下降线",
            genre: .pop,
            roman: "I-V-vi-iii-IV-I-IV-V",
            practiceKey: "C 大调",
            chords: ["C", "G", "Am", "Em", "F", "C", "F", "G"],
            feel: "叙事感强、适合分解伴奏",
            practiceTip: "先两拍一个和弦练顺，再把低音按 C-G-A-E-F-C-F-G 单独弹清楚。",
            zhSongExamples: [
                SongExample(title: "童话", artist: "光良"),
                SongExample(title: "蒲公英的约定", artist: "周杰伦"),
                SongExample(title: "那些年", artist: "胡夏"),
            ],
            enSongExamples: [
                SongExample(title: "Canon in D", artist: "Johann Pachelbel"),
                SongExample(title: "Memories", artist: "Maroon 5"),
                SongExample(title: "Basket Case", artist: "Green Day"),
            ]
        ),
        CommonChordProgression(
            title: "三和弦民谣骨架",
            genre: .folkCountry,
            roman: "I-IV-V",
            practiceKey: "G 大调",
            chords: ["G", "C", "D"],
            feel: "开放、直接、适合唱伴奏",
            practiceTip: "用 G-C-D 练基本切换，再加入 D7 感受回到 G 的拉力。",
            zhSongExamples: [
                SongExample(title: "外婆的澎湖湾", artist: "潘安邦"),
                SongExample(title: "乡间的小路", artist: "齐豫"),
                SongExample(title: "朋友", artist: "周华健"),
            ],
            enSongExamples: [
                SongExample(title: "Blowin' in the Wind", artist: "Bob Dylan"),
                SongExample(title: "Twist and Shout", artist: "The Beatles"),
                SongExample(title: "La Bamba", artist: "Ritchie Valens"),
            ]
        ),
        CommonChordProgression(
            title: "12 小节布鲁斯",
            genre: .blues,
            roman: "I7-IV7-V7",
            practiceKey: "A 大调布鲁斯",
            chords: ["A7", "D7", "A7", "A7", "D7", "D7", "A7", "A7", "E7", "D7", "A7", "E7"],
            feel: "Shuffle、摇摆、适合练节奏稳定",
            practiceTip: "用八分 Shuffle 右手，先只换 A7/D7/E7；熟后加入 turnaround。",
            zhSongExamples: [
                SongExample(title: "一块红布", artist: "崔健"),
                SongExample(title: "花房姑娘", artist: "崔健"),
                SongExample(title: "钟鼓楼", artist: "何勇"),
            ],
            enSongExamples: [
                SongExample(title: "Sweet Home Chicago", artist: "Robert Johnson"),
                SongExample(title: "Johnny B. Goode", artist: "Chuck Berry"),
                SongExample(title: "Rock and Roll", artist: "Led Zeppelin"),
            ]
        ),
        CommonChordProgression(
            title: "爵士 ii-V-I",
            genre: .jazzSoul,
            roman: "ii7-V7-Imaj7",
            practiceKey: "C 大调",
            chords: ["Dm7", "G7", "Cmaj7"],
            feel: "爵士标准、强解决感",
            practiceTip: "先每个和弦一小节，重点听 G7 解决到 Cmaj7；再练四度圈移调。",
            zhSongExamples: [
                SongExample(title: "夜上海", artist: "周璇"),
                SongExample(title: "玫瑰玫瑰我爱你", artist: "姚莉"),
                SongExample(title: "不了情", artist: "顾媚"),
            ],
            enSongExamples: [
                SongExample(title: "Autumn Leaves", artist: "Joseph Kosma"),
                SongExample(title: "Fly Me to the Moon", artist: "Bart Howard"),
                SongExample(title: "Take the A Train", artist: "Duke Ellington"),
            ]
        ),
        CommonChordProgression(
            title: "摇滚 bVII 借用和弦",
            genre: .rock,
            roman: "I-bVII-IV",
            practiceKey: "D 大调",
            chords: ["D", "C", "G"],
            feel: "开放、粗粝、适合强力扫弦",
            practiceTip: "D 到 C 保持开放弦共鸣，右手用稳定下扫或十六分闷音制造推进。",
            zhSongExamples: [
                SongExample(title: "一无所有", artist: "崔健"),
                SongExample(title: "新长征路上的摇滚", artist: "崔健"),
                SongExample(title: "假行僧", artist: "崔健"),
            ],
            enSongExamples: [
                SongExample(title: "Sweet Home Alabama", artist: "Lynyrd Skynyrd"),
                SongExample(title: "Werewolves of London", artist: "Warren Zevon"),
                SongExample(title: "All Summer Long", artist: "Kid Rock"),
            ]
        ),
        CommonChordProgression(
            title: "流行朋克推进",
            genre: .rock,
            roman: "I-V-vi-IV",
            practiceKey: "D 大调",
            chords: ["D", "A", "Bm", "G"],
            feel: "明快、有冲刺感",
            practiceTip: "可先用强力和弦 D5-A5-B5-G5，再换回完整开放/横按和弦。",
            zhSongExamples: [
                SongExample(title: "倔强", artist: "五月天"),
                SongExample(title: "知足", artist: "五月天"),
                SongExample(title: "我相信", artist: "杨培安"),
            ],
            enSongExamples: [
                SongExample(title: "When I Come Around", artist: "Green Day"),
                SongExample(title: "Dammit", artist: "blink-182"),
                SongExample(title: "Complicated", artist: "Avril Lavigne"),
            ]
        ),
        CommonChordProgression(
            title: "Andalusian 小调下行",
            genre: .latin,
            roman: "i-bVII-bVI-V",
            practiceKey: "A 小调",
            chords: ["Am", "G", "F", "E"],
            feel: "西班牙感、戏剧化、适合轮指/扫弦",
            practiceTip: "Am-G-F-E 先慢速扫弦，E 可换 E7 加强回到 Am 的张力。",
            zhSongExamples: [
                SongExample(title: "一生所爱", artist: "卢冠廷"),
                SongExample(title: "心墙", artist: "郭静"),
                SongExample(title: "囚鸟", artist: "彭羚"),
            ],
            enSongExamples: [
                SongExample(title: "Hit the Road Jack", artist: "Ray Charles"),
                SongExample(title: "Sultans of Swing", artist: "Dire Straits"),
                SongExample(title: "Smooth", artist: "Santana feat. Rob Thomas"),
            ]
        ),
    ]
}

#Preview {
    NavigationStack {
        CommonChordProgressionsView()
    }
}
