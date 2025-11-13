use criterion::{black_box, criterion_group, criterion_main, BenchmarkId, Criterion};
use test_utils::{
    mock_data::MockData,
    payment_instruction_generator::PaymentInstructionGenerator,
    test_helpers::{create_test_config, generate_proof, TestScenario},
};

fn bench_proof_generation_simple(c: &mut Criterion) {
    let config = create_test_config(TestScenario::Fast);
    let input = MockData::simple_valid_input();

    c.bench_function("proof_generation_simple", |b| {
        b.iter(|| {
            let result = generate_proof(black_box(&input), black_box(&config));
            // Note: This will likely fail in benchmarks since we don't have actual RISC Zero setup
            // but it demonstrates the benchmark structure
            black_box(result)
        })
    });
}

fn bench_proof_generation_batch(c: &mut Criterion) {
    let config = create_test_config(TestScenario::Fast);
    let mut generator = PaymentInstructionGenerator::new();

    let mut group = c.benchmark_group("proof_generation_batch");

    for size in [1, 5, 10].iter() {
        let inputs = generator.generate_batch(*size);

        group.bench_with_input(BenchmarkId::new("batch_size", size), size, |b, _| {
            b.iter(|| {
                for input in &inputs {
                    let result = generate_proof(black_box(input), black_box(&config));
                    let _ = black_box(result);
                }
            })
        });
    }

    group.finish();
}

fn bench_proof_generation_edge_cases(c: &mut Criterion) {
    let config = create_test_config(TestScenario::Fast);
    let mut generator = PaymentInstructionGenerator::new();
    let edge_cases = generator.generate_edge_cases();

    let mut group = c.benchmark_group("proof_generation_edge_cases");

    for (i, input) in edge_cases.iter().enumerate() {
        group.bench_with_input(BenchmarkId::new("edge_case", i), &i, |b, _| {
            b.iter(|| {
                let result = generate_proof(black_box(input), black_box(&config));
                black_box(result)
            })
        });
    }

    group.finish();
}

criterion_group!(
    benches,
    bench_proof_generation_simple,
    bench_proof_generation_batch,
    bench_proof_generation_edge_cases
);
criterion_main!(benches);
