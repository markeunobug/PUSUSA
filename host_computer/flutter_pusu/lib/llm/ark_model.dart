enum ArkModel {
  doubaoSeed21Turbo(
    displayName: 'Doubao-Seed-2.1-turbo',
    modelId: 'doubao-seed-2-1-turbo-260628',
    description: '效果、速度和成本均衡（推荐）',
  ),
  doubaoSeed21Pro(
    displayName: 'Doubao-Seed-2.1-pro',
    modelId: 'doubao-seed-2-1-pro-260628',
    description: '复杂任务、编程与多模态能力更强',
  ),
  doubaoSeedEvolving(
    displayName: 'Doubao-Seed-Evolving',
    modelId: 'doubao-seed-evolving-latest-version',
    description: '持续升级的综合旗舰，支持超长上下文',
  ),
  doubaoSeedCharacter(
    displayName: 'Doubao-Seed-Character',
    modelId: 'doubao-seed-character-260628',
    description: '人格化对话与虚拟陪伴',
  ),
  glm52(
    displayName: 'GLM-5.2',
    modelId: 'glm-5-2-260617',
    description: '复杂编程和开发任务',
  ),
  deepSeekV4Pro(
    displayName: 'DeepSeek-V4-pro',
    modelId: 'deepseek-v4-pro-260425',
    description: '旗舰混合推理，优先回答精度',
  ),
  deepSeekV4Flash(
    displayName: 'DeepSeek-V4-flash',
    modelId: 'deepseek-v4-flash-260425',
    description: '混合推理，优先速度和成本',
  );

  const ArkModel({
    required this.displayName,
    required this.modelId,
    required this.description,
  });

  final String displayName;
  final String modelId;
  final String description;
}
