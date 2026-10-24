// Desenha o ícone do ViewTube (1024 px) e grava em PNG.
//   swift scripts/make-icon.swift saida.png
//
// Parente do ícone do YouTube Music (fundo vermelho, anel branco, play no centro), mas próprio:
// squircle do macOS em degradê rosa → vermelho, anel partido em dois arcos (os dois modos) e
// play de cantos arredondados.
import AppKit

let size: CGFloat = 1024
let output = CommandLine.arguments.dropFirst().first ?? "icon.png"

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
    // Corpo no grid da Apple: 824 px centrados, cantos contínuos.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = NSBezierPath(roundedRect: body, xRadius: 186, yRadius: 186)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    NSColor.black.setFill()
    shape.fill()
    ctx.restoreGState()

    ctx.saveGState()
    shape.addClip()
    // Fundo: rosa no alto à esquerda → vermelho → vermelho escuro embaixo à direita.
    NSGradient(colors: [
        NSColor(srgbRed: 1.00, green: 0.42, blue: 0.60, alpha: 1),
        NSColor(srgbRed: 0.96, green: 0.13, blue: 0.24, alpha: 1),
        NSColor(srgbRed: 0.72, green: 0.04, blue: 0.16, alpha: 1),
    ])!.draw(in: body, angle: -50)
    // Brilho suave no topo (vidro).
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.22), NSColor.white.withAlphaComponent(0)])!
        .draw(in: CGRect(x: body.minX, y: body.midY + 40, width: body.width, height: body.height / 2 - 40), angle: -90)
    ctx.restoreGState()

    let center = CGPoint(x: 512, y: 512)
    // Anel em dois arcos com aberturas opostas: YouTube ⇄ Music.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 18, color: NSColor.black.withAlphaComponent(0.18).cgColor)
    ctx.setStrokeColor(NSColor.white.cgColor)
    ctx.setLineWidth(46)
    ctx.setLineCap(.round)
    let ringRadius: CGFloat = 262
    let gap: CGFloat = 0.30   // radianos de cada abertura
    for start in [CGFloat.pi * 0.25, CGFloat.pi * 1.25] {
        ctx.addArc(center: center, radius: ringRadius, startAngle: start + gap / 2,
                   endAngle: start + .pi - gap / 2, clockwise: false)
        ctx.strokePath()
    }
    // Play de cantos arredondados, um pouco à direita para ficar opticamente centrado.
    ctx.addPath(roundedTriangle(center: CGPoint(x: 530, y: 512), radius: 150, corner: 38))
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
