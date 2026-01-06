
use bincode;

fn main() {
    println!("=== Simple Bincode Example (like Nim example.nim) ===\n");

    let original = vec![1u8, 2, 3, 4, 5];
    println!("Original bytes: {:?}", original);

    let serialized = bincode::encode_to_vec(&original, bincode::config::standard())
        .expect("Failed to serialize");
    println!("Serialized length: {}", serialized.len());
    println!("Serialized bytes: {:?}", serialized);

    let (deserialized, _): (Vec<u8>, _) = bincode::decode_from_slice(
        &serialized,
        bincode::config::standard(),
    )
    .expect("Failed to deserialize");

    println!("Deserialized bytes: {:?}", deserialized);
    println!("Match: {}\n", original == deserialized);

    let text = "Hello, bincode!";
    println!("Original string: {}", text);
    let text_bytes = text.as_bytes().to_vec();
    let serialized_text = bincode::encode_to_vec(&text_bytes, bincode::config::standard())
        .expect("Failed to serialize string");

    println!("Serialized length: {}", serialized_text.len());
    println!("Serialized Text: {:?}", serialized_text);
    
    let (deserialized_bytes, _): (Vec<u8>, _) = bincode::decode_from_slice(
        &serialized_text,
        bincode::config::standard(),
    )
    .expect("Failed to deserialize string");

    let deserialized_text = String::from_utf8(deserialized_bytes)
        .expect("Failed to convert bytes to string");
    println!("Deserialized string: {}", deserialized_text);
    println!("Match: {}\n", text == deserialized_text);

    // Serialize an empty array
    let empty_array: Vec<u8> = vec![];
    println!("Original empty array: {:?}", empty_array);
    let serialized_empty = bincode::encode_to_vec(&empty_array, bincode::config::standard())
        .expect("Failed to serialize empty array");
    println!("Serialized empty array length: {}", serialized_empty.len());
    println!("Serialized empty array bytes: {:?}", serialized_empty);

    let (deserialized_empty, _): (Vec<u8>, _) = bincode::decode_from_slice(
        &serialized_empty,
        bincode::config::standard(),
    )
    .expect("Failed to deserialize empty array");

    println!("Deserialized empty array: {:?}", deserialized_empty);
    println!("Match: {}", empty_array == deserialized_empty);
}

