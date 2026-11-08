//! Cookie `PREF` do YouTube (`PrefCookie.swift`): idioma (`hl`), país (`gl`) e o modo restrito
//! (bit 0x8000000 do campo `f2`, em hexadecimal). Cada mudança devolve um cookie novo, com os
//! outros campos na mesma ordem.

const RESTRICTED_BIT: u64 = 0x8000000;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PrefCookie {
    pub fields: Vec<(String, String)>,
}

impl PrefCookie {
    pub fn parse(raw: &str) -> Self {
        let fields = raw
            .split('&')
            .filter(|p| !p.is_empty())
            .filter_map(|pair| {
                let (key, value) = pair.split_once('=').unwrap_or((pair, ""));
                (!key.is_empty()).then(|| (key.to_string(), value.to_string()))
            })
            .collect();
        Self { fields }
    }

    pub fn raw(&self) -> String {
        self.fields.iter().map(|(k, v)| format!("{k}={v}")).collect::<Vec<_>>().join("&")
    }

    pub fn get(&self, key: &str) -> Option<&str> {
        self.fields.iter().find(|(k, _)| k == key).map(|(_, v)| v.as_str())
    }

    pub fn language(&self) -> Option<&str> {
        self.get("hl")
    }

    pub fn country(&self) -> Option<&str> {
        self.get("gl")
    }

    pub fn restricted(&self) -> bool {
        self.flags() & RESTRICTED_BIT != 0
    }

    /// Troca o valor no lugar (ou acrescenta no fim); `None` remove o campo.
    pub fn setting(&self, key: &str, value: Option<&str>) -> Self {
        let Some(value) = value else {
            return Self { fields: self.fields.iter().filter(|(k, _)| k != key).cloned().collect() };
        };
        let mut fields = self.fields.clone();
        match fields.iter_mut().find(|(k, _)| k == key) {
            Some(field) => field.1 = value.to_string(),
            None => fields.push((key.to_string(), value.to_string())),
        }
        Self { fields }
    }

    pub fn with_restricted(&self, on: bool) -> Self {
        let next = if on { self.flags() | RESTRICTED_BIT } else { self.flags() & !RESTRICTED_BIT };
        let hex = format!("{next:x}");
        self.setting("f2", if next == 0 { None } else { Some(&hex) })
    }

    fn flags(&self) -> u64 {
        self.get("f2").and_then(|v| u64::from_str_radix(v, 16).ok()).unwrap_or(0)
    }
}
