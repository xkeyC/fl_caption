//! User word lists: corrections applied to recognized text, and the
//! glossary (terms and their translations) given to the translator.

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Replacement {
    pub from: String,
    pub to: String,
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Term {
    pub source: String,
    pub target: String,
}

/// Applies `rules` in order. ASCII letters match case-insensitively (ASR
/// capitalizes at will); everything else matches exactly.
pub fn apply_replacements(text: &str, rules: &[Replacement]) -> String {
    let mut text = text.to_string();
    for rule in rules {
        if rule.from.is_empty() {
            continue;
        }
        text = replace_ignoring_ascii_case(&text, &rule.from, &rule.to);
    }
    text
}

fn replace_ignoring_ascii_case(text: &str, from: &str, to: &str) -> String {
    let lower_text = text.to_ascii_lowercase();
    let lower_from = from.to_ascii_lowercase();
    // ASCII lowercasing keeps every byte offset, so offsets found in the
    // lowercased copy index the original.
    let mut out = String::with_capacity(text.len());
    let mut at = 0;
    while let Some(found) = lower_text[at..].find(&lower_from) {
        let start = at + found;
        out.push_str(&text[at..start]);
        out.push_str(to);
        at = start + from.len();
    }
    out.push_str(&text[at..]);
    out
}

/// The terms whose source occurs in `text`, longest first, at most `limit`.
pub fn matching_terms<'a>(text: &str, terms: &'a [Term], limit: usize) -> Vec<&'a Term> {
    let lower = text.to_ascii_lowercase();
    let mut found: Vec<&Term> = terms
        .iter()
        .filter(|term| !term.source.trim().is_empty() && !term.target.trim().is_empty())
        .filter(|term| lower.contains(&term.source.trim().to_ascii_lowercase()))
        .collect();
    found.sort_by_key(|term| std::cmp::Reverse(term.source.len()));
    found.dedup_by(|a, b| a.source.eq_ignore_ascii_case(&b.source));
    found.truncate(limit);
    found
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn replacements_ignore_ascii_case_only() {
        let rules = [Replacement {
            from: "port olisar".into(),
            to: "Port Olisar".into(),
        }];
        assert_eq!(
            apply_replacements("go to PORT olisar now", &rules),
            "go to Port Olisar now"
        );
        let cjk = [Replacement {
            from: "笑乐".into(),
            to: "小乐".into(),
        }];
        assert_eq!(apply_replacements("笑乐你好", &cjk), "小乐你好");
    }

    #[test]
    fn terms_match_longest_first() {
        let terms = [
            Term {
                source: "Hornet".into(),
                target: "大黄蜂".into(),
            },
            Term {
                source: "Super Hornet".into(),
                target: "超级大黄蜂".into(),
            },
            Term {
                source: "Gladius".into(),
                target: "短剑".into(),
            },
        ];
        let found = matching_terms("my super hornet is ready", &terms, 8);
        assert_eq!(found.len(), 2);
        assert_eq!(found[0].source, "Super Hornet");
    }
}
