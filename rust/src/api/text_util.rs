use rayon::prelude::*;
use std::collections::HashMap;

/// 计算字符串中重复字符的数量
pub async fn count_duplicate_characters(input: String) -> usize {
    let char_counts = input
        .par_chars() // 使用 rayon 并行迭代字符
        .fold(HashMap::new, |mut acc, c| {
            *acc.entry(c).or_insert(0) += 1;
            acc
        })
        .reduce(HashMap::new, |mut acc, map| {
            for (k, v) in map {
                *acc.entry(k).or_insert(0) += v;
            }
            acc
        });

    char_counts.values().filter(|&&count| count > 1).sum()
}

