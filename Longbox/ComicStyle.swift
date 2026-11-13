import SwiftUI

/// Longbox's look: flat print colors, ink outlines, hard offset shadows, halftone dots.
enum Theme {
    static let ink = Color(red: 0.07, green: 0.063, blue: 0.11)
    static let panel = Color(red: 0.135, green: 0.122, blue: 0.205)
    static let paper = Color(red: 0.965, green: 0.937, blue: 0.85)
    static let yellow = Color(red: 1.0, green: 0.824, blue: 0.118)
    static let orange = Color(red: 1.0, green: 0.60, blue: 0.11)
    static let red = Color(red: 0.91, green: 0.196, blue: 0.173)
    static let cyan = Color(red: 0.17, green: 0.72, blue: 0.9)

    static let accent = yellow

    /// The display face. Falls back to the system font if the file is missing.
    static func display(_ size: CGFloat) -> Font {
        .custom("Bangers-Regular", size: size, relativeTo: .title)
    }

    static func caption(_ size: CGFloat = 12) -> Font {
        .system(size: size, weight: .heavy)
    }
}

// MARK: Ink panel

/// Clips to a panel shape, outlines it, and drops a hard offset shadow behind it.
struct InkPanel: ViewModifier {
    var corner: CGFloat = 4
    var line: CGFloat = 2.5
    var offset: CGFloat = 4
    var stroke: Color = .black
    var shadow: Color = .black

    func body(content: Content) -> some View {
        content
            .clipShape(RoundedRectangle(cornerRadius: corner))
            .overlay(RoundedRectangle(cornerRadius: corner).strokeBorder(stroke, lineWidth: line))
            .background(
                RoundedRectangle(cornerRadius: corner)
                    .fill(shadow)
                    .offset(x: offset, y: offset)
            )
    }
}

extension View {
    func inkPanel(
        corner: CGFloat = 4,
        line: CGFloat = 2.5,
        offset: CGFloat = 4,
        stroke: Color = .black,
        shadow: Color = .black
    ) -> some View {
        modifier(InkPanel(corner: corner, line: line, offset: offset, stroke: stroke, shadow: shadow))
    }
}

// MARK: Halftone

/// A field of printer's dots that fades toward the bottom-right corner.
struct Halftone: View {
    var color: Color
    var spacing: CGFloat = 11
    var maxRadius: CGFloat = 3.6

    var body: some View {
        Canvas { context, size in
            guard size.width > 0, size.height > 0 else { return }
            let columns = Int(size.width / spacing) + 2
            let rows = Int(size.height / (spacing * 0.5)) + 2
            for row in 0..<rows {
                let y = CGFloat(row) * spacing * 0.5
                let shift: CGFloat = row % 2 == 0 ? 0 : spacing * 0.5
                for column in 0..<columns {
                    let x = CGFloat(column) * spacing + shift
                    let fade = 1 - (x / size.width) * 0.55 - (y / size.height) * 0.65
                    let radius = maxRadius * max(0, min(1, fade))
                    if radius > 0.35 {
                        let dot = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
                        context.fill(Path(ellipseIn: dot), with: .color(color))
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: Lettering

/// A narration box, used for section labels.
struct CaptionBox: View {
    let text: String
    var fill: Color = Theme.yellow
    var shadow: Color = Theme.red
    var size: CGFloat = 12

    var body: some View {
        Text(text.uppercased())
            .font(Theme.caption(size))
            .italic()
            .kerning(0.6)
            .foregroundColor(.black)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(fill)
            .overlay(Rectangle().strokeBorder(Color.black, lineWidth: 2))
            .background(Rectangle().fill(shadow).offset(x: 3, y: 3))
    }
}

/// A non-interactive lettered pill, for labels that sit inside a larger button.
struct ComicPill: View {
    let text: String
    var fill: Color = Theme.red
    var textColor: Color = Theme.paper

    var body: some View {
        Text(text)
            .font(Theme.display(22))
            .foregroundColor(textColor)
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 6).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.black, lineWidth: 2.5))
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.black).offset(x: 3, y: 3))
    }
}

struct ComicButtonStyle: ButtonStyle {
    var fill: Color = Theme.yellow
    var shadow: Color = Theme.red
    var textColor: Color = .black
    var size: CGFloat = 24

    func makeBody(configuration: Configuration) -> some View {
        let down = configuration.isPressed
        return configuration.label
            .font(Theme.display(size))
            .foregroundColor(textColor)
            .padding(.horizontal, size)
            .padding(.vertical, size * 0.375)
            .background(RoundedRectangle(cornerRadius: 6).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.black, lineWidth: 2.5))
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(shadow)
                    .offset(x: down ? 0 : 4, y: down ? 0 : 4)
            )
            .offset(x: down ? 4 : 0, y: down ? 4 : 0)
            .animation(.easeOut(duration: 0.08), value: down)
    }
}

/// A light press response for large tappable panels.
struct PressDownStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// A round toolbar button.
struct RoundIcon: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 16, weight: .black))
            .foregroundColor(.black)
            .frame(width: 42, height: 42)
            .background(Circle().fill(Theme.yellow))
            .overlay(Circle().strokeBorder(Color.black, lineWidth: 2.5))
            .background(Circle().fill(Theme.red).offset(x: 3, y: 3))
    }
}

// MARK: Shapes

/// A spiky burst, for call-outs.
struct Burst: Shape {
    var points: Int = 12
    var inner: CGFloat = 0.72

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerRadius = min(rect.width, rect.height) / 2
        let innerRadius = outerRadius * inner
        for step in 0..<(points * 2) {
            let angle = CGFloat(step) * .pi / CGFloat(points) - .pi / 2
            let radius = step % 2 == 0 ? outerRadius : innerRadius
            let point = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
            if step == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }
}

struct BurstBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Theme.display(15))
            .foregroundColor(.black)
            .frame(width: 52, height: 52)
            .background(Burst().fill(Theme.yellow))
            .background(Burst().stroke(Color.black, lineWidth: 4))
            .rotationEffect(.degrees(12))
    }
}

struct StampBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Theme.display(20))
            .foregroundColor(Theme.red)
            .padding(.horizontal, 10)
            .padding(.vertical, 2)
            .background(Theme.paper)
            .overlay(Rectangle().strokeBorder(Theme.red, lineWidth: 2.5))
            .rotationEffect(.degrees(-14))
    }
}

/// A speech bubble with a tail at the bottom left. The tail takes the bottom 24 points.
struct SpeechBubble: Shape {
    func path(in rect: CGRect) -> Path {
        let tail: CGFloat = 24
        let body = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: max(rect.height - tail, 0))
        var path = Path()
        path.addRoundedRect(in: body, cornerSize: CGSize(width: 22, height: 22))
        path.move(to: CGPoint(x: body.minX + 44, y: body.maxY - 2))
        path.addLine(to: CGPoint(x: body.minX + 30, y: rect.maxY))
        path.addLine(to: CGPoint(x: body.minX + 78, y: body.maxY - 2))
        path.closeSubpath()
        return path
    }
}

// MARK: Progress

struct ChunkyProgress: View {
    let value: Double
    var fill: Color = Theme.red
    var track: Color = Theme.paper
    var border: Color = .black
    var height: CGFloat = 12

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(track)
                Rectangle()
                    .fill(fill)
                    .frame(width: max(0, geo.size.width * CGFloat(min(max(value, 0), 1))))
            }
        }
        .frame(height: height)
        .overlay(Rectangle().strokeBorder(border, lineWidth: 2))
    }
}
