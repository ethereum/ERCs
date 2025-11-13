use criterion::{black_box, criterion_group, criterion_main, BenchmarkId, Criterion};
use test_utils::{
    crypto_utils::{compute_leaf_hash, keccak256, poseidon_hash},
    merkle_tree::MerkleTree,
    mock_data::MockData,
    proof_validator::ProofValidator,
};

fn bench_hash_functions(c: &mut Criterion) {
    let data = b"test data for hashing benchmark";
    let left = [1u8; 32];
    let right = [2u8; 32];

    let mut group = c.benchmark_group("hash_functions");

    group.bench_function("keccak256", |b| {
        b.iter(|| {
            let result = keccak256(black_box(data));
            black_box(result)
        })
    });

    group.bench_function("poseidon_hash", |b| {
        b.iter(|| {
            let result = poseidon_hash(black_box(&left), black_box(&right));
            black_box(result)
        })
    });

    group.bench_function("compute_leaf_hash", |b| {
        b.iter(|| {
            let result = compute_leaf_hash(black_box(data), black_box(1u8));
            black_box(result)
        })
    });

    group.finish();
}

fn bench_merkle_tree_operations(c: &mut Criterion) {
    let mut group = c.benchmark_group("merkle_tree");

    for size in [4, 8, 16, 32].iter() {
        // Create owned string data to avoid lifetime issues
        let string_data: Vec<String> = (0..*size).map(|i| format!("leaf_{}", i)).collect();
        let tree_data: Vec<(&[u8], u8)> = string_data
            .iter()
            .enumerate()
            .map(|(i, s)| (s.as_bytes(), (i % 256) as u8))
            .collect();

        group.bench_with_input(BenchmarkId::new("tree_creation", size), size, |b, _| {
            b.iter(|| {
                let tree = MerkleTree::new(black_box(tree_data.clone()));
                black_box(tree)
            })
        });

        // Benchmark proof generation
        let tree = MerkleTree::new(tree_data.clone());
        group.bench_with_input(BenchmarkId::new("proof_generation", size), size, |b, _| {
            b.iter(|| {
                let proof = tree.generate_proof(black_box(0));
                black_box(proof)
            })
        });

        // Benchmark proof verification
        let proof = tree.generate_proof(0).unwrap();
        let leaf = tree.leaves[0];
        let root = tree.root();
        group.bench_with_input(
            BenchmarkId::new("proof_verification", size),
            size,
            |b, _| {
                b.iter(|| {
                    let result = MerkleTree::verify_proof(
                        black_box(&leaf),
                        black_box(&proof),
                        black_box(&root),
                    );
                    black_box(result)
                })
            },
        );
    }

    group.finish();
}

fn bench_input_validation(c: &mut Criterion) {
    let valid_input = MockData::simple_valid_input();
    let invalid_inputs = MockData::error_cases();

    let mut group = c.benchmark_group("input_validation");

    group.bench_function("valid_input", |b| {
        b.iter(|| {
            let result = ProofValidator::validate_input_consistency(black_box(&valid_input));
            black_box(result)
        })
    });

    for (name, input) in invalid_inputs {
        group.bench_with_input(BenchmarkId::new("invalid_input", name), &name, |b, _| {
            b.iter(|| {
                let result = ProofValidator::validate_input_consistency(black_box(&input));
                black_box(result)
            })
        });
    }

    group.finish();
}

fn bench_json_validation(c: &mut Criterion) {
    let valid_json = r#"{"name": "Alice Smith", "account": "123456789"}"#;
    let invalid_json = r#"{"name": "Alice Smith", "account": 123456789"#; // Missing closing brace
    let complex_json = r#"{"name": "José María García-López", "account": "ES1234567890", "address": {"street": "Calle Mayor 123", "city": "Madrid", "country": "Spain"}, "metadata": {"created": "2024-01-01", "updated": "2024-12-31"}}"#;

    let mut group = c.benchmark_group("json_validation");

    group.bench_function("valid_simple", |b| {
        b.iter(|| {
            let result = ProofValidator::validate_json_format(black_box(valid_json));
            black_box(result)
        })
    });

    group.bench_function("invalid_simple", |b| {
        b.iter(|| {
            let result = ProofValidator::validate_json_format(black_box(invalid_json));
            black_box(result)
        })
    });

    group.bench_function("valid_complex", |b| {
        b.iter(|| {
            let result = ProofValidator::validate_json_format(black_box(complex_json));
            black_box(result)
        })
    });

    group.finish();
}

fn bench_date_validation(c: &mut Criterion) {
    let valid_dates = ["20240101", "20241231", "20991231"];
    let invalid_dates = ["2024-01-01", "20241301", "20241232", "invalid"];

    let mut group = c.benchmark_group("date_validation");

    for date in valid_dates.iter() {
        group.bench_with_input(BenchmarkId::new("valid_date", date), date, |b, date| {
            b.iter(|| {
                let result = ProofValidator::validate_date_format(black_box(date));
                black_box(result)
            })
        });
    }

    for date in invalid_dates.iter() {
        group.bench_with_input(BenchmarkId::new("invalid_date", date), date, |b, date| {
            b.iter(|| {
                let result = ProofValidator::validate_date_format(black_box(date));
                black_box(result)
            })
        });
    }

    group.finish();
}

criterion_group!(
    benches,
    bench_hash_functions,
    bench_merkle_tree_operations,
    bench_input_validation,
    bench_json_validation,
    bench_date_validation
);
criterion_main!(benches);
