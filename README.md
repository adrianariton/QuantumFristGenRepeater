# Chart flow of the protocol

```
sequenceDiagram
    Alice-->>Alice: FIND_FREE_QUBIT
    Alice->>+John: FIND_QUBIT_TO_PAIR
    John->>John: WAIT_UNTIL_FOUND
    John-->>-Alice: ASSIGN_ORIGIN or UNLOCK (if not found)
    Alice->>+John: INITIALIZE_STATE
    John->>-Alice: GENERATED_ENTANGLEMENT
    Alice->>+John(process_channel): GENERATED_ENTANGLEMENT
    John(process_channel)->>Alice: LOCK Alice
    John(process_channel)-->>John(process_channel): LOCK and WAIT FOR length(indices) == purif_circuit_size
    John(process_channel)->>-John(process_channel): Perform purification measurement and send it to Alice

    John(process_channel)->>+Alice(process_channel): PURIFY(local_measurement)
    Alice(process_channel)->>Alice(process_channel): Perform purification measurement and compare to John
    Alice(process_channel)->>John(process_channel): REPORT_SUCCESS
    Alice(process_channel)->>-Alice(process_channel): Release locks and clear registers based on success
    John(process_channel)->>John(process_channel): Release locks and clear registers based on success
```

![sequence](https://github.com/adrianariton/QuantumFirstGenRepeater/blob/master/flow.png?raw=true)
