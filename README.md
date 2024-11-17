
Task with [yukimemi/spyrun: Check file notify and run.](https://github.com/yukimemi/spyrun)

```mermaid
sequenceDiagram
    participant spyrun(bin)
    participant spyrun(system/user)
    participant LocalDir
    participant FileServer

    FileServer->>spyrun(bin): Detect file Create or Modify
    spyrun(bin)-->>FileServer: Copy file to LocalDir
    spyrun(bin)->>LocalDir: File copied
    LocalDir->>spyrun(system/user): Notify spyrun(system/user) of new file
    spyrun(system/user)-->>LocalDir: Execute new file
```

## Directory struct.

### Remote

```mermaid
graph TD
  A[spyrun_task] -->|bin| B{bin}
  B --> C[spyrun.exe]
  B --> D[spyrun.toml]
  B --> E[init.ps1]
  A -->|core| F{core}
  F --> G{cfg}
  G --> H[common.ps1]
  G --> AI[launch.js]
  F --> I{cmd}
  I --> J{global}
  J --> K[hoge.cmd]
  I --> L{local}
  L --> M{pc1}
  M --> N[hoge.cmd]
  L --> O{pc2}
  O --> P[fuga.cmd]
  A -->|system| Q{system}
  Q --> R{cfg}
  R --> S[spyrun.toml]
  Q --> T{cmd}
  T --> U{global}
  U --> V[hoge.cmd]
  T --> W{local}
  W --> X{pc1}
  X --> Y[hoge.cmd]
  A -->|user| Z{user}
  Z --> AA{cfg}
  AA --> AB[spyrun.toml]
  Z --> AC{cmd}
  AC --> AD{global}
  AD --> AE[hoge.cmd]
  AC --> AF{local}
  AF --> AG{pc1}
  AG --> AH[hoge.cmd]
```


```mermaid
graph LR
  A[spyrun_task] --> B{bin}
  B --> C[spyrun.exe]
  B --> D[spyrun.toml]
  B --> E[init.ps1]
  A --> F{core}
  F --> G{cfg}
  G --> H[common.ps1]
  F --> I{cmd}
  I --> J{global}
  J --> K[hoge.cmd]
  I --> L{local}
  L --> M{pc1}
  M --> N[hoge.cmd]
  L --> O{pc2}
  O --> P[fuga.cmd]
  A --> Q{system}
  Q --> R{cfg}
  R --> S[spyrun.toml]
  Q --> T{cmd}
  T --> U{global}
  U --> V[hoge.cmd]
  T --> W{local}
  W --> X{pc1}
  X --> Y[hoge.cmd]
  A --> Z{user}
  Z --> AA{cfg}
  AA --> AB[spyrun.toml]
  Z --> AC{cmd}
  AC --> AD{global}
  AD --> AE[hoge.cmd]
  AC --> AF{local}
  AF --> AG{pc1}
  AG --> AH[hoge.cmd]
```

- spyrun_task
  - bin
    - spyrun.exe
    - spyrun.toml
    - init.ps1
  - core
    - cfg
      - common.ps1
    - cmd
      - global
        - hoge.cmd
      - local
        - pc1
          - hoge.cmd
        - pc2
          - fuga.cmd
  - system
    - cfg
      - spyrun.toml
    - cmd
      - global
        - hoge.cmd
      - local
        - pc1
          - hoge.cmd
  - user
    - cfg
      - spyrun.toml
    - cmd
      - global
        - hoge.cmd
      - local
        - pc1
          - hoge.cmd

