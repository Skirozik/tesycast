import SwiftUI
import Combine

// MARK: - Internal Models

private struct ShootingParticle {
    var x: Double
    var y: Double
    let angleDeg: Double
    let speed: Double
    var distance: Double = 0
    let starColor: Color
    let trailColor: Color

    var scale: Double { max(1.0, 1.0 + distance / 120.0) }

    mutating func advance() {
        let rad = angleDeg * .pi / 180
        x += speed * cos(rad)
        y += speed * sin(rad)
        distance += speed
    }

    func isOff(w: Double, h: Double) -> Bool {
        x < -60 || x > w + 60 || y < -60 || y > h + 60
    }
}

private struct TwinkleStar {
    let nx: Double      // 0…1 normalized
    let ny: Double
    let size: Double
    let baseOpacity: Double
    let phase: Double
}

// MARK: - Animator

private final class StarAnimator: ObservableObject {

    struct LayerConfig {
        let starColor: Color
        let trailColor: Color
        let minSpeed: Double
        let maxSpeed: Double
        let minDelay: Double
        let maxDelay: Double
    }

    let layers: [LayerConfig] = [
        LayerConfig(
            starColor: Color(red: 0.62, green: 0.0, blue: 1.0),
            trailColor: Color(red: 0.18, green: 0.73, blue: 0.87),
            minSpeed: 8, maxSpeed: 18, minDelay: 1.0, maxDelay: 3.0
        ),
        LayerConfig(
            starColor: Color(red: 1.0, green: 0.0, blue: 0.6),
            trailColor: Color(red: 1.0, green: 0.72, blue: 0.0),
            minSpeed: 6, maxSpeed: 14, minDelay: 2.0, maxDelay: 4.0
        ),
        LayerConfig(
            starColor: Color(red: 0.0, green: 1.0, blue: 0.62),
            trailColor: Color(red: 0.0, green: 0.72, blue: 1.0),
            minSpeed: 10, maxSpeed: 20, minDelay: 1.5, maxDelay: 3.5
        ),
    ]

    @Published var particles: [Int: ShootingParticle] = [:]
    var screenSize: CGSize = .zero
    var startTime: Date = Date()

    let twinkleStars: [TwinkleStar] = (0..<80).map { _ in
        TwinkleStar(
            nx: Double.random(in: 0...1),
            ny: Double.random(in: 0...1),
            size: Double.random(in: 0.7...2.2),
            baseOpacity: Double.random(in: 0.25...0.85),
            phase: Double.random(in: 0...(.pi * 2))
        )
    }

    func configure(size: CGSize) {
        screenSize = size
        startTime = Date()
        for i in layers.indices {
            scheduleSpawn(index: i)
        }
    }

    private func scheduleSpawn(index: Int) {
        let cfg = layers[index]
        let delay = Double.random(in: cfg.minDelay...cfg.maxDelay)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            let w = self.screenSize.width
            let h = self.screenSize.height
            guard w > 0, h > 0 else { return }
            let side = Int.random(in: 0...3)
            let x: Double, y: Double, angle: Double
            switch side {
            case 0:  x = Double.random(in: 0...w); y = -10;     angle = 45
            case 1:  x = w + 10; y = Double.random(in: 0...h);  angle = 135
            case 2:  x = Double.random(in: 0...w); y = h + 10;  angle = 225
            default: x = -10;    y = Double.random(in: 0...h);  angle = 315
            }
            self.particles[index] = ShootingParticle(
                x: x, y: y, angleDeg: angle,
                speed: Double.random(in: cfg.minSpeed...cfg.maxSpeed),
                starColor: cfg.starColor,
                trailColor: cfg.trailColor
            )
        }
    }

    func tick(size: CGSize) {
        screenSize = size
        for (i, var p) in particles {
            p.advance()
            if p.isOff(w: size.width, h: size.height) {
                particles.removeValue(forKey: i)
                scheduleSpawn(index: i)
            } else {
                particles[i] = p
            }
        }
    }
}

// MARK: - View

struct ShootingStarsBackground: View {
    @StateObject private var animator = StarAnimator()

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { tl in
                Canvas { ctx, size in
                    // Deep-space background
                    ctx.fill(
                        Path(CGRect(origin: .zero, size: size)),
                        with: .color(Color(red: 0.016, green: 0.016, blue: 0.055))
                    )

                    // Twinkling star field
                    let elapsed = tl.date.timeIntervalSince(animator.startTime)
                    for star in animator.twinkleStars {
                        let wave = (sin(elapsed * 0.7 + star.phase) + 1) / 2
                        let opacity = star.baseOpacity * (0.3 + 0.7 * wave)
                        let x = star.nx * size.width
                        let y = star.ny * size.height
                        let r = star.size / 2
                        ctx.fill(
                            Path(ellipseIn: CGRect(x: x - r, y: y - r,
                                                   width: star.size, height: star.size)),
                            with: .color(.white.opacity(opacity))
                        )
                    }

                    // Shooting stars
                    for (_, p) in animator.particles {
                        let sw = 10.0 * p.scale
                        let sh = 1.5
                        let rad = p.angleDeg * .pi / 180
                        let transform = CGAffineTransform(translationX: p.x, y: p.y)
                            .rotated(by: rad)
                        let path = Path(CGRect(x: 0, y: -sh / 2, width: sw, height: sh))
                            .applying(transform)
                        ctx.fill(path, with: .linearGradient(
                            Gradient(stops: [
                                .init(color: p.trailColor.opacity(0), location: 0),
                                .init(color: p.starColor,              location: 1),
                            ]),
                            startPoint: CGPoint(x: p.x, y: p.y),
                            endPoint: CGPoint(
                                x: p.x + sw * cos(rad),
                                y: p.y + sw * sin(rad)
                            )
                        ))
                    }
                }
                .onChange(of: tl.date) { _, _ in
                    animator.tick(size: geo.size)
                }
            }
            .onAppear {
                animator.configure(size: geo.size)
            }
        }
        .ignoresSafeArea()
    }
}
