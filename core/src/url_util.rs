//! Pedaços de URL com a mesma semântica do Foundation usada no app do Mac.
//! - Query: `+` continua `+` (como `URLComponents.queryItems`; não é formulário), o primeiro valor vence.
//! - Codificação de valores: só `A-Z a-z 0-9 - . _ ~` passam (como `urlQueryValueAllowed`).

use std::collections::HashMap;

/// `a=1&b=%20x&a=2` → {a: "1", b: " x"}. Itens sem `=` valem "".
pub(crate) fn query_map(query: Option<&str>) -> HashMap<String, String> {
    let mut map = HashMap::new();
    let Some(query) = query else { return map };
    for pair in query.split('&') {
        if pair.is_empty() {
            continue;
        }
        let (name, value) = match pair.split_once('=') {
            Some((n, v)) => (n, v),
            None => (pair, ""),
        };
        map.entry(percent_decode(name)).or_insert_with(|| percent_decode(value));
    }
    map
}

pub(crate) fn percent_decode(text: &str) -> String {
    let bytes = text.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'%' && i + 2 < bytes.len() {
            if let (Some(h), Some(l)) = (hex(bytes[i + 1]), hex(bytes[i + 2])) {
                out.push(h * 16 + l);
                i += 3;
                continue;
            }
        }
        out.push(bytes[i]);
        i += 1;
    }
    String::from_utf8_lossy(&out).into_owned()
}

fn hex(b: u8) -> Option<u8> {
    match b {
        b'0'..=b'9' => Some(b - b'0'),
        b'a'..=b'f' => Some(b - b'a' + 10),
        b'A'..=b'F' => Some(b - b'A' + 10),
        _ => None,
    }
}

/// Valor seguro numa query: tudo fora de `A-Za-z0-9-._~` vira `%XX` (UTF-8).
pub(crate) fn encode_value(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    for b in text.bytes() {
        if b.is_ascii_alphanumeric() || matches!(b, b'-' | b'.' | b'_' | b'~') {
            out.push(b as char);
        } else {
            out.push_str(&format!("%{b:02X}"));
        }
    }
    out
}

/// Esquema de um texto (`https`, `viewtube`, `mailto`), em minúsculas; `None` sem esquema.
pub(crate) fn scheme_of(text: &str) -> Option<String> {
    let colon = text.find(':')?;
    let scheme = &text[..colon];
    let mut chars = scheme.chars();
    let first = chars.next()?;
    if !first.is_ascii_alphabetic() || !chars.all(|c| c.is_ascii_alphanumeric() || matches!(c, '+' | '-' | '.')) {
        return None;
    }
    Some(scheme.to_ascii_lowercase())
}

/// Partes de um link de esquema próprio (`viewtube://host/caminho?query`), sem normalizar nada.
pub(crate) struct CustomUrl<'a> {
    pub host: Option<String>,
    pub path: &'a str,
    pub query: Option<&'a str>,
}

pub(crate) fn split_custom(text: &str) -> Option<CustomUrl<'_>> {
    let colon = text.find(':')?;
    let rest = &text[colon + 1..];
    let rest = rest.split('#').next().unwrap_or("");
    let (before_query, query) = match rest.split_once('?') {
        Some((b, q)) => (b, Some(q)),
        None => (rest, None),
    };
    let Some(authority_and_path) = before_query.strip_prefix("//") else {
        return Some(CustomUrl { host: None, path: before_query, query });
    };
    let end = authority_and_path.find('/').unwrap_or(authority_and_path.len());
    let authority = &authority_and_path[..end];
    // Como o Foundation: sem usuário e sem porta no host.
    let host = authority.rsplit('@').next().unwrap_or("");
    let host = host.split(':').next().unwrap_or("");
    Some(CustomUrl {
        host: if host.is_empty() { None } else { Some(host.to_lowercase()) },
        path: &authority_and_path[end..],
        query,
    })
}

/// Componentes de caminho sem os vazios (`/a//b/` → ["a", "b"]), como `URL.pathComponents.dropFirst()`.
pub(crate) fn path_components(path: &str) -> Vec<String> {
    path.split('/').filter(|p| !p.is_empty()).map(percent_decode).collect()
}

/// `URL.path` do Foundation: sem a barra final (menos na raiz).
pub(crate) fn foundation_path(path: &str) -> &str {
    if path.len() > 1 {
        path.trim_end_matches('/')
    } else {
        path
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn query_keeps_plus_and_first_value() {
        let q = query_map(Some("a=1+2&b=%20x&a=3&c"));
        assert_eq!(q["a"], "1+2");
        assert_eq!(q["b"], " x");
        assert_eq!(q["c"], "");
    }

    #[test]
    fn decode_handles_broken_sequences() {
        assert_eq!(percent_decode("100%"), "100%");
        assert_eq!(percent_decode("%zz%41"), "%zzA");
        assert_eq!(percent_decode("%C3%A7"), "ç");
    }

    #[test]
    fn custom_url_parts() {
        let u = split_custom("viewtube://Speed/1.5?x=1#f").unwrap();
        assert_eq!(u.host.as_deref(), Some("speed"));
        assert_eq!(u.path, "/1.5");
        assert_eq!(u.query, Some("x=1"));
        assert!(split_custom("viewtube:open").unwrap().host.is_none());
    }
}
