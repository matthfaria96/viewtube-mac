import Foundation

/// Favorito "Abrir no ViewTube": pausa o vídeo no navegador e manda link + posição para o app.
public enum Bookmarklet {
    public static let source = """
    javascript:(()=>{const v=document.querySelector('video');const t=v?Math.floor(v.currentTime):0;\
    if(v)v.pause();location.href='\(IncomingLink.scheme)://open?url='+encodeURIComponent(location.href)+'&t='+t;})()
    """
}
