// Desenha o ícone do ViewTube (1024 px) e grava em PNG.
//   swift scripts/make-icon.swift saida.png
//
// Parente do ícone do YouTube Music (fundo vermelho, anel branco, play no centro), mas próprio:
// squircle do macOS em degradê rosa → vermelho, anel partido em dois arcos (os dois modos) e
// play de cantos arredondados. Borda de vidro (aro escuro por dentro e reflexo no topo) como os
// outros apps do witchmymac: sem ela, o vermelho chapado até a borda parecia maior que os irmãos.
import AppKit

let size: CGFloat = 1024
let output = CommandLine.arguments.dropFirst().first ?? "icon.png"

/// Squircle de cantos contínuos (superelipse n = 5), o mesmo perfil de canto dos ícones da Apple.
func squircle(in rect: CGRect, exponent n: CGFloat = 5, steps: Int = 720) -> CGPath {
    let path = CGMutablePath()
    let a = rect.width / 2, b = rect.height / 2
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = pow(abs(c), 2 / n) * a * (c < 0 ? -1 : 1)
        let y = pow(abs(s), 2 / n) * b * (s < 0 ? -1 : 1)
        let point = CGPoint(x: rect.midX + x, y: rect.midY + y)
        i == 0 ? path.move(to: point) : path.addLine(to: point)
    }
    path.closeSubpath()
    return path
}

func roundedTriangle(center: CGPoint, radius: CGFloat, corner: CGFloat) -> CGPath {
    let points = (0..<3).map { i -> CGPoint in
        let angle = CGFloat(i) * 2 * .pi / 3
        return CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
    }
    let path = CGMutablePath()
    path.move(to: CGPoint(x: (points[0].x + points[1].x) / 2, y: (points[0].y + points[1].y) / 2))
    for i in 1...3 {
        path.addArc(tangent1End: points[i % 3], tangent2End: points[(i + 1) % 3], radius: corner)
    }
    path.closeSubpath()
    return path
}

let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
    guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
    // Corpo no grid da Apple: 824 px centrados.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = squircle(in: body)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    ctx.addPath(shape)
    ctx.setFillColor(NSColor.black.cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    // Fundo: rosa no alto à esquerda → vermelho → vermelho escuro embaixo à direita (um tom mais fundo).
    NSGradient(colors: [
        NSColor(srgbRed: 0.97, green: 0.34, blue: 0.50, alpha: 1),
        NSColor(srgbRed: 0.88, green: 0.09, blue: 0.21, alpha: 1),
        NSColor(srgbRed: 0.55, green: 0.02, blue: 0.11, alpha: 1),
    ])!.draw(in: body, angle: -50)
    // Brilho suave no topo (vidro).
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.16), NSColor.white.withAlphaComponent(0)])!
        .draw(in: CGRect(x: body.minX, y: body.midY + 60, width: body.width, height: body.height / 2 - 60), angle: -90)
    // Aro escuro por dentro: fecha o ícone nas bordas.
    ctx.addPath(shape)
    ctx.setLineWidth(40)
    ctx.setStrokeColor(NSColor(srgbRed: 0.25, green: 0, blue: 0.06, alpha: 0.16).cgColor)
    ctx.strokePath()
    ctx.addPath(shape)
    ctx.setLineWidth(8)
    ctx.setStrokeColor(NSColor(srgbRed: 0.18, green: 0, blue: 0.04, alpha: 0.22).cgColor)
    ctx.strokePath()
    ctx.restoreGState()

    // Reflexo fino no aro, mais forte no alto (vidro).
    ctx.saveGState()
    ctx.addPath(squircle(in: body.insetBy(dx: 5, dy: 5)))
    ctx.setLineWidth(3)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.45), NSColor.white.withAlphaComponent(0.05), NSColor.white.withAlphaComponent(0.12)])!
        .draw(in: body, angle: -90)
    ctx.restoreGState()

    let center = CGPoint(x: 512, y: 512)
    // Anel em dois arcos com aberturas opostas: YouTube ⇄ Music.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 20, color: NSColor.black.withAlphaComponent(0.25).cgColor)
    ctx.setStrokeColor(NSColor.white.cgColor)
    ctx.setLineWidth(40)
    ctx.setLineCap(.round)
    let ringRadius: CGFloat = 238
    let gap: CGFloat = 0.30   // radianos de cada abertura
    for start in [CGFloat.pi * 0.25, CGFloat.pi * 1.25] {
        ctx.addArc(center: center, radius: ringRadius, startAngle: start + gap / 2,
                   endAngle: start + .pi - gap / 2, clockwise: false)
        ctx.strokePath()
    }
    // Play de cantos arredondados, um pouco à direita para ficar opticamente centrado.
    ctx.addPath(roundedTriangle(center: CGPoint(x: 528, y: 512), radius: 136, corner: 34))
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.fillPath()
    ctx.restoreGState()
    return true
}

guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("não foi possível gerar o PNG\n".data(using: .utf8)!)
    exit(1)
}
try png.write(to: URL(fileURLWithPath: output))
