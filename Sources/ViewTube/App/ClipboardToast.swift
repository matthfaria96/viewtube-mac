import AppKit
import SwiftUI
import ViewTubeCore

/// Pílula "Abrir link copiado" que aparece no topo quando o usuário volta para o app com um
/// link do YouTube na área de transferência (copiado em outro navegador). Some sozinha.
@MainActor
final class ClipboardToastModel: ObservableObject {
    @Published private(set) var offer: ClipboardOffer?
    private var lastChangeCount = NSPasteboard.general.changeCount
    private var hideTask: Task<Void, Never>?

    /// Chamado ao ativar o app. Só olha a área de transferência se ela mudou desde a última vez.
    func check(currentVideoID: String?) {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        guard let text = pasteboard.string(forType: .string),
              let offer = ClipboardOffer.evaluate(text: text, currentVideoID: currentVideoID) else { return }
        show(offer)
    }

    /// O app mesmo copiou (Copiar Link): não oferecer de volta.
    func ignoreCurrentClipboard() {
        lastChangeCount = NSPasteboard.general.changeCount
    }

    func dismiss() {
        hideTask?.cancel()
        withAnimation(.spring(duration: 0.3)) { offer = nil }
    }

    private func show(_ offer: ClipboardOffer) {
        withAnimation(.spring(duration: 0.35)) { self.offer = offer }
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }
}

struct ClipboardToastView: View {
    @ObservedObject var model: ClipboardToastModel
    let open: (OpenRequest) -> Void

    var body: some View {
        // Só a pílula: a camada tem o tamanho dela e some quando não há oferta.
        Group {
            if let offer = model.offer {
                pill(offer)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.top, 12)
    }

    private func pill(_ offer: ClipboardOffer) -> some View {
        HStack(spacing: 10) {
            Image(systemName: offer.request.mode == .music ? "music.note" : "play.rectangle.fill")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text("Abrir link copiado")
                    .font(.system(size: 13, weight: .semibold))
                Text(offer.label)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Button("Abrir") {
                open(offer.request)
                model.dismiss()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            Button {
                model.dismiss()
            } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Dispensar")
            .accessibilityLabel("Dispensar")
        }
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .padding(.vertical, 8)
        .modifier(GlassCapsule())
        .frame(maxWidth: 420)
    }
}

/// Liquid Glass no macOS 26+, material translúcido antes disso.
private struct GlassCapsule: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: .capsule)
        } else {
            content
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
                .shadow(color: .black.opacity(0.25), radius: 16, y: 6)
        }
    }
}

/// Conteúdo da janela: a página do modo atual e, por cima, a pílula (do tamanho dela,
/// escondida sem oferta). Trocar de modo só troca a página; nada recarrega.
final class PlayerContainerView: NSView {
    private let toast: NSView
    private(set) var page: NSView?
    let progress = NavigationProgressModel()
    private lazy var progressView: NSView = {
        let view = PassthroughHostingView(rootView: NavigationProgressView(model: progress))
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    private var skeleton: NSView?

    /// Esqueleto cinza animado por cima da página enquanto ela carrega. Sai num esmaecimento (a página
    /// já está desenhada por baixo, com a mesma geometria): troca limpa, sem salto de layout.
    /// `frozen`/`alpha` só para a ferramenta de desenvolvimento (esqueleto parado, translúcido).
    func setLoading(_ loading: Bool, mode: PlayerMode = .youtube, shape: LoadingSkeletonView.Shape = .player,
                    frozen: Bool = false, alpha: CGFloat = 1, animated: Bool = true) {
        let root = LoadingSkeletonView(mode: mode, shape: shape, frozen: frozen)
        if loading, let current = skeleton as? NSHostingView<LoadingSkeletonView> {
            current.rootView = root
            current.layer?.removeAllAnimations()
            current.alphaValue = alpha
            return
        }
        if loading, skeleton == nil {
            let view = NSHostingView(rootView: root)
            view.translatesAutoresizingMaskIntoConstraints = false
            // Entra num esmaecimento curto (sem relance); parado (ferramenta de desenvolvimento), direto.
            view.alphaValue = frozen ? alpha : 0
            addSubview(view, positioned: .below, relativeTo: toast)
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: leadingAnchor), view.trailingAnchor.constraint(equalTo: trailingAnchor),
                view.topAnchor.constraint(equalTo: topAnchor), view.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
            skeleton = view
            if !frozen {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.14
                    view.animator().alphaValue = alpha
                }
            }
        } else if !loading, let view = skeleton {
            skeleton = nil
            guard animated else { view.removeFromSuperview(); return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.32
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                view.animator().alphaValue = 0
            }, completionHandler: { view.removeFromSuperview() })
        }
    }

    init(webView: NSView, toast: NSView) {
        self.toast = toast
        super.init(frame: .zero)
        wantsLayer = true
        toast.translatesAutoresizingMaskIntoConstraints = false
        addSubview(toast)
        addSubview(progressView)
        NSLayoutConstraint.activate([
            toast.centerXAnchor.constraint(equalTo: centerXAnchor),
            toast.topAnchor.constraint(equalTo: topAnchor),
            progressView.leadingAnchor.constraint(equalTo: leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: trailingAnchor),
            progressView.topAnchor.constraint(equalTo: topAnchor),
            progressView.heightAnchor.constraint(equalToConstant: 3),
        ])
        show(webView)
    }

    func show(_ webView: NSView) {
        guard webView !== page else { return }
        // Troca de modo: esmaecimento curto feito pelo Core Animation (nativo, sem custo de página).
        if page != nil, let layer {
            let fade = CATransition()
            fade.type = .fade
            fade.duration = 0.22
            fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(fade, forKey: "modeSwitch")
        }
        page?.removeFromSuperview()
        webView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(webView, positioned: .below, relativeTo: skeleton ?? toast)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        page = webView
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) não usado") }
}

/// Hospeda SwiftUI sem capturar cliques (a linha de progresso fica por cima da página).
final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Andamento da navegação interna (0…1) ou nil (sem navegação).
@MainActor
final class NavigationProgressModel: ObservableObject {
    @Published var value: Double?
}

/// Linha rosa fina logo abaixo da barra, seguindo o andamento real da página; some ao terminar.
struct NavigationProgressView: View {
    @ObservedObject var model: NavigationProgressModel

    var body: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(ModeSwitchView.gradient)
                .frame(width: geo.size.width * CGFloat(model.value ?? 1))
                .shadow(color: Color(red: 0.94, green: 0.13, blue: 0.24).opacity(0.6), radius: 3)
                .opacity(model.value == nil ? 0 : 1)
                .animation(.easeOut(duration: 0.25), value: model.value)
        }
        .accessibilityHidden(true)
    }
}
