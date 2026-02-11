use std::time::Instant;
use bincode;

/// Variable-length encoding config (LEB128)
/// Uses a large limit to accommodate all benchmark sizes (10 MB + overhead)
fn variable_config() -> impl bincode::config::Config {
    bincode::config::standard()
        .with_little_endian()
        .with_variable_int_encoding()
        .with_limit::<20971520>() // 20 MB limit
}

/// Fixed 8-byte encoding config
/// Uses a large limit to accommodate all benchmark sizes (10 MB + overhead)
fn fixed8_config() -> impl bincode::config::Config {
    bincode::config::standard()
        .with_little_endian()
        .with_fixed_int_encoding()
        .with_limit::<20971520>() // 20 MB limit
}

fn benchmark_serialize(data: &[u8], config: impl bincode::config::Config, iterations: usize) -> f64 {
    let start = Instant::now();
    for _ in 0..iterations {
        let _ = bincode::encode_to_vec(data, config).unwrap();
    }
    let elapsed = start.elapsed();
    elapsed.as_secs_f64() / iterations as f64
}

fn benchmark_deserialize(encoded: &[u8], config: impl bincode::config::Config, iterations: usize) -> f64 {
    let start = Instant::now();
    for _ in 0..iterations {
        let _: Vec<u8> = bincode::decode_from_slice(encoded, config).unwrap().0;
    }
    let elapsed = start.elapsed();
    elapsed.as_secs_f64() / iterations as f64
}

fn run_benchmark(name: &str, data: &[u8], iterations: usize) {
    println!("\n=== {} ({} bytes, {} iterations) ===", name, data.len(), iterations);
    
    // Variable encoding
    let config_var = variable_config();
    let encoded_var = bincode::encode_to_vec(data, config_var).unwrap();
    
    let serialize_time_var = benchmark_serialize(data, config_var, iterations);
    let deserialize_time_var = benchmark_deserialize(&encoded_var, config_var, iterations);
    
    println!("Variable encoding:");
    println!("  Serialize:   {:.4} ms/op", serialize_time_var * 1000.0);
    println!("  Deserialize: {:.4} ms/op", deserialize_time_var * 1000.0);
    println!("  Throughput:  {:.2} MB/s (serialize), {:.2} MB/s (deserialize)", 
        (data.len() as f64 / 1024.0 / 1024.0) / serialize_time_var,
        (data.len() as f64 / 1024.0 / 1024.0) / deserialize_time_var);
    
    // Fixed 8-byte encoding
    let config_fixed = fixed8_config();
    let encoded_fixed = bincode::encode_to_vec(data, config_fixed).unwrap();
    
    let serialize_time_fixed = benchmark_serialize(data, config_fixed, iterations);
    let deserialize_time_fixed = benchmark_deserialize(&encoded_fixed, config_fixed, iterations);
    
    println!("Fixed 8-byte encoding:");
    println!("  Serialize:   {:.4} ms/op", serialize_time_fixed * 1000.0);
    println!("  Deserialize: {:.4} ms/op", deserialize_time_fixed * 1000.0);
    println!("  Throughput:  {:.2} MB/s (serialize), {:.2} MB/s (deserialize)", 
        (data.len() as f64 / 1024.0 / 1024.0) / serialize_time_fixed,
        (data.len() as f64 / 1024.0 / 1024.0) / deserialize_time_fixed);
}

fn main() {
    println!("Rust Bincode Performance Benchmarks");
    println!("====================================");
    
    // Small data (1 KB)
    let small_data = vec![0u8; 1024];
    run_benchmark("Small data", &small_data, 10000);
    
    // Medium data (64 KB)
    let medium_data = vec![0u8; 64 * 1024];
    run_benchmark("Medium data", &medium_data, 1000);
    
    // Large data (1 MB)
    let large_data = vec![0u8; 1024 * 1024];
    run_benchmark("Large data", &large_data, 100);
    
    // Very large data (10 MB)
    let very_large_data = vec![0u8; 10 * 1024 * 1024];
    run_benchmark("Very large data", &very_large_data, 10);
    
    println!("\n=== Benchmark complete ===");
}
