import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/material.dart' as material;
import 'package:record/record.dart';

import '../asr/volcengine_asr_client.dart';
import '../asr/volcengine_asr_config.dart';
import '../asr/volcengine_asr_protocol.dart';
import '../agent/agent_request_policy.dart';
import '../agent/instrument_agent.dart';
import '../llm/ark_chat_client.dart';
import '../llm/ark_chat_message.dart';
import '../llm/ark_config.dart';
import '../llm/ark_model.dart';
import '../tts/tts_audio_player.dart';
import '../tts/volcengine_tts_client.dart';
import '../tts/volcengine_tts_config.dart';
import 'assistant_response_formatter.dart';

enum AiConversationState {
  idle,
  connecting,
  listening,
  recognizing,
  thinking,
  error,
}

class AiAssistantPanel extends StatefulWidget {
  const AiAssistantPanel({
    super.key,
    required this.onClose,
    required this.onListeningChanged,
    required this.instrumentAgent,
  });

  final VoidCallback onClose;
  final ValueChanged<bool> onListeningChanged;
  final InstrumentAgentGateway instrumentAgent;

  @override
  State<AiAssistantPanel> createState() => AiAssistantPanelState();
}

class AiAssistantPanelState extends State<AiAssistantPanel>
    with SingleTickerProviderStateMixin {
  static const int _frameBytes = 6400;
  static const int _maxContextMessages = 60;
  static const int _maxToolRounds = 12;

  static const Color _surface = Color(0xF21B1D22);
  static const Color _surfaceElevated = Color(0xFF25282E);
  static const Color _surfaceMuted = Color(0xFF30343B);
  static const Color _border = Color(0xFF444952);
  static const Color _mutedText = Color(0xFFADB3BE);
  static const Color _accent = Color(0xFF65A9FF);
  static const Color _recording = Color(0xFFE5484D);

  final AudioRecorder _recorder = AudioRecorder();
  final VolcengineAsrClient _asrClient = VolcengineAsrClient();
  final ArkChatClient _arkClient = ArkChatClient();
  final VolcengineTtsClient _ttsClient = VolcengineTtsClient();
  final TtsAudioPlayer _ttsPlayer = TtsAudioPlayer();
  final ScrollController _chatScrollController = ScrollController();
  final TextEditingController _textController = TextEditingController();
  final FocusNode _textFocusNode = FocusNode();
  final List<int> _pendingBytes = <int>[];
  final Map<ArkModel, List<ArkChatMessage>> _conversationByModel =
      <ArkModel, List<ArkChatMessage>>{
    for (final model in ArkModel.values) model: <ArkChatMessage>[],
  };
  final Map<ArkModel, String> _responseModelIds = <ArkModel, String>{};

  StreamSubscription<Uint8List>? _audioSubscription;
  StreamSubscription<VolcengineAsrServerMessage>? _messageSubscription;
  late final AnimationController _pulseController;
  Uint8List? _heldFrame;
  Timer? _resultTimeout;
  AiConversationState _state = AiConversationState.idle;
  ArkModel _selectedModel = ArkModel.deepSeekV4Pro;
  String _liveTranscript = '';
  String? _errorText;
  bool _finalResultHandled = false;
  bool _speechEnabled = false;
  bool _isSynthesizing = false;
  bool _panelVisible = false;
  bool _executingTools = false;
  InstrumentAgentMode _agentMode = InstrumentAgentMode.agent;
  _PendingInstrumentPlan? _pendingPlan;
  List<InstrumentToolResult> _lastToolResults = <InstrumentToolResult>[];
  int _ttsGeneration = 0;
  int _modelRequestGeneration = 0;

  List<ArkChatMessage> get _messages => _conversationByModel[_selectedModel]!;

  String? get _lastResponseModelId => _responseModelIds[_selectedModel];

  bool get _isBusy =>
      _state == AiConversationState.connecting ||
      _state == AiConversationState.recognizing ||
      _state == AiConversationState.thinking ||
      _executingTools ||
      _pendingPlan != null;

  bool get isListening => _state == AiConversationState.listening;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _messageSubscription = _asrClient.messages.listen(
      _handleAsrMessage,
      onError: (Object error, StackTrace stackTrace) {
        unawaited(_abortAsrSession());
        _showError(_friendlyError(error));
      },
    );
  }

  @override
  void dispose() {
    widget.onListeningChanged(false);
    _resultTimeout?.cancel();
    unawaited(_audioSubscription?.cancel());
    unawaited(_messageSubscription?.cancel());
    _pulseController.dispose();
    _chatScrollController.dispose();
    _textController.dispose();
    _textFocusNode.dispose();
    _arkClient.dispose();
    _ttsClient.dispose();
    unawaited(_ttsPlayer.dispose());
    unawaited(_recorder.dispose());
    unawaited(_asrClient.dispose());
    super.dispose();
  }

  void focusTextInput() {
    _panelVisible = true;
    _textFocusNode.requestFocus();
  }

  void showPanel() {
    _panelVisible = true;
  }

  Future<void> prepareToHide() async {
    _panelVisible = false;
    _ttsGeneration++;
    await _ttsPlayer.stop();
    if (_state == AiConversationState.connecting ||
        _state == AiConversationState.listening ||
        _state == AiConversationState.recognizing) {
      await _abortAsrSession();
      if (!mounted) return;
      setState(() {
        _state = AiConversationState.idle;
        _isSynthesizing = false;
      });
    } else if (mounted) {
      setState(() => _isSynthesizing = false);
    }
  }

  Future<void> _toggleRecording() async {
    if (_state == AiConversationState.listening) {
      await _stopRecording();
    } else if (!_isBusy) {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    if (!VolcengineAsrConfig.isConfigured) {
      _showError('请先在 volcengine_asr_config.dart 中填写豆包语音 API Key');
      return;
    }

    _ttsGeneration++;
    await _ttsPlayer.stop();
    _textController.clear();
    setState(() {
      _state = AiConversationState.connecting;
      _liveTranscript = '';
      _errorText = null;
      _finalResultHandled = false;
      _isSynthesizing = false;
    });

    try {
      if (!await _recorder.hasPermission()) {
        throw StateError('没有麦克风权限，请在 Windows 设置中允许应用访问麦克风');
      }
      _pendingBytes.clear();
      _heldFrame = null;
      await _asrClient.connect();
      final audioStream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
          autoGain: true,
          echoCancel: true,
          noiseSuppress: true,
        ),
      );
      _audioSubscription = audioStream.listen(
        _handleAudioChunk,
        onError: (Object error, StackTrace stackTrace) {
          unawaited(_abortAsrSession());
          _showError(_friendlyError(error));
        },
      );
      if (!mounted) return;
      setState(() => _state = AiConversationState.listening);
      widget.onListeningChanged(true);
    } catch (error) {
      await _abortAsrSession();
      _showError(_friendlyError(error));
    }
  }

  Future<void> _stopRecording() async {
    widget.onListeningChanged(false);
    setState(() => _state = AiConversationState.recognizing);
    try {
      await _recorder.stop();
      await _audioSubscription?.cancel();
      _audioSubscription = null;
      _sendFinalAudioFrame();
      _resultTimeout?.cancel();
      _resultTimeout = Timer(const Duration(seconds: 12), () {
        _showError('等待最终识别结果超时，请重试');
        unawaited(_asrClient.close());
      });
    } catch (error) {
      await _abortAsrSession();
      _showError(_friendlyError(error));
    }
  }

  void _handleAudioChunk(Uint8List chunk) {
    _pendingBytes.addAll(chunk);
    while (_pendingBytes.length >= _frameBytes) {
      final frame = Uint8List.fromList(_pendingBytes.sublist(0, _frameBytes));
      _pendingBytes.removeRange(0, _frameBytes);
      final previous = _heldFrame;
      if (previous != null) _asrClient.sendAudio(previous);
      _heldFrame = frame;
    }
  }

  void _sendFinalAudioFrame() {
    final held = _heldFrame;
    final remainder = Uint8List.fromList(_pendingBytes);
    _pendingBytes.clear();
    _heldFrame = null;

    if (held != null && remainder.isNotEmpty) {
      _asrClient.sendAudio(held);
      _asrClient.sendAudio(remainder, isLast: true);
    } else if (held != null) {
      _asrClient.sendAudio(held, isLast: true);
    } else {
      _asrClient.sendAudio(remainder, isLast: true);
    }
  }

  void _handleAsrMessage(VolcengineAsrServerMessage message) {
    if (message.isError) {
      _showError('ASR ${message.errorCode}: ${message.errorMessage ?? '未知错误'}');
      unawaited(_abortAsrSession());
      return;
    }

    final text = message.text;
    if (text != null && text.isNotEmpty) {
      _liveTranscript = text;
      _textController.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
      if (mounted) {
        setState(() {});
        _scrollToBottom();
      }
    }

    if (!message.isFinal || _finalResultHandled) return;
    _finalResultHandled = true;
    _resultTimeout?.cancel();
    unawaited(_asrClient.close());
    widget.onListeningChanged(false);

    final finalText = _textController.text.trim();
    if (finalText.isEmpty) {
      _showError('没有识别到有效语音，请靠近麦克风后重试');
      return;
    }
    unawaited(_sendToModel(finalText));
  }

  Future<void> _sendToModel(String text) async {
    final requestModel = _selectedModel;
    final messages = _conversationByModel[requestModel]!;
    final userMessage = ArkChatMessage(role: ArkChatRole.user, content: text);

    if (!ArkConfig.isConfigured) {
      if (!mounted) return;
      setState(() {
        messages.add(userMessage);
        _liveTranscript = '';
        _textController.clear();
      });
      _scrollToBottom();
      _showError('内容已保留，但尚未配置方舟 API Key，暂时无法发送给大模型');
      return;
    }

    if (!mounted) return;
    setState(() {
      messages.add(userMessage);
      _liveTranscript = '';
      _textController.clear();
      _errorText = null;
      _responseModelIds.remove(requestModel);
      _pendingPlan = null;
      _lastToolResults = <InstrumentToolResult>[];
    });
    _scrollToBottom();

    await _requestModelResponse(requestModel, toolRound: 0);
  }

  Future<void> _requestModelResponse(
    ArkModel requestModel, {
    required int toolRound,
    Set<String> seenToolFingerprints = const <String>{},
    int mutationEpoch = 0,
    bool allowTools = true,
  }) async {
    final requestGeneration = ++_modelRequestGeneration;
    final messages = _conversationByModel[requestModel]!;
    var contextStart = messages.length > _maxContextMessages
        ? messages.length - _maxContextMessages
        : 0;
    while (contextStart < messages.length &&
        messages[contextStart].role == ArkChatRole.tool) {
      contextStart++;
    }
    final context = messages.sublist(contextStart);
    final assistantIndex = messages.length;
    if (!mounted) return;
    setState(() {
      messages.add(const ArkChatMessage(
        role: ArkChatRole.assistant,
        content: '',
      ));
      _state = AiConversationState.thinking;
      _errorText = null;
    });

    var answer = '';
    final toolAccumulators = <int, _ToolCallAccumulator>{};
    try {
      await for (final event in _arkClient.streamReply(
        model: requestModel,
        messages: context,
        tools: _agentMode == InstrumentAgentMode.chat || !allowTools
            ? const <Map<String, dynamic>>[]
            : AgentRequestPolicy.filterToolDefinitions(
                widget.instrumentAgent.toolDefinitions,
                allowDataAnalysis: AgentRequestPolicy.requestsDataAnalysis(
                  _latestUserRequest(messages),
                ),
                allowMeasurementStart:
                    AgentRequestPolicy.requestsMeasurementStart(
                  _latestUserRequest(messages),
                ),
              ),
      )) {
        if (requestGeneration != _modelRequestGeneration) return;
        answer += event.content;
        for (final delta in event.toolCallDeltas) {
          final accumulator = toolAccumulators.putIfAbsent(
            delta.index,
            () => _ToolCallAccumulator(),
          );
          accumulator.add(delta);
        }
        if (!mounted) return;
        setState(() {
          final responseModelId = event.responseModelId;
          if (responseModelId != null && responseModelId.isNotEmpty) {
            _responseModelIds[requestModel] = responseModelId;
          }
          messages[assistantIndex] =
              messages[assistantIndex].copyWith(content: answer);
        });
        _scrollToBottom();
      }

      if (requestGeneration != _modelRequestGeneration) return;

      final toolCalls = toolAccumulators.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key));
      final parsedCalls =
          toolCalls.map((entry) => entry.value.build()).toList();
      if (parsedCalls.isNotEmpty) {
        if (toolRound >= _maxToolRounds) {
          throw const ArkApiException('Agent 连续工具调用超过安全轮数限制');
        }
        final displayText = answer.trim().isEmpty
            ? '已生成仪器操作计划，请检查后确认。'
            : AssistantResponseFormatter.toPlainText(answer);
        final instrumentCalls = parsedCalls
            .map(
              (call) => InstrumentToolCall(
                id: call.id,
                name: call.name,
                arguments: call.arguments,
              ),
            )
            .toList();
        if (!mounted) return;
        setState(() {
          messages[assistantIndex] = ArkChatMessage(
            role: ArkChatRole.assistant,
            content: displayText,
            toolCalls: parsedCalls,
          );
          _state = AiConversationState.idle;
          _pendingPlan = _PendingInstrumentPlan(
            model: requestModel,
            calls: instrumentCalls,
            toolRound: toolRound,
            seenToolFingerprints: seenToolFingerprints,
            mutationEpoch: mutationEpoch,
          );
        });
        _scrollToBottom();
        if (_agentMode == InstrumentAgentMode.agent ||
            instrumentCalls.every(
              (call) => widget.instrumentAgent.isReadOnly(call.name),
            )) {
          await _executePendingPlan();
        }
        return;
      }

      if (answer.trim().isEmpty) {
        throw const ArkApiException('模型没有返回可显示的文本');
      }
      final plainAnswer = AssistantResponseFormatter.toPlainText(answer);
      if (!mounted) return;
      setState(() {
        messages[assistantIndex] =
            messages[assistantIndex].copyWith(content: plainAnswer);
        _state = AiConversationState.idle;
      });
      if (_speechEnabled && _panelVisible) {
        unawaited(_speakAnswer(plainAnswer));
      }
    } catch (error) {
      if (requestGeneration != _modelRequestGeneration ||
          error is ArkRequestCancelledException) {
        return;
      }
      if (!mounted) return;
      setState(() {
        if (answer.isEmpty && assistantIndex < messages.length) {
          messages.removeAt(assistantIndex);
        }
      });
      _showError(_friendlyError(error));
    }
  }

  Future<void> _stopThinking() async {
    if (_state != AiConversationState.thinking) return;
    _modelRequestGeneration++;
    _arkClient.cancelActiveRequest();
    _ttsGeneration++;
    await _ttsPlayer.stop();
    if (!mounted) return;
    setState(() {
      final messages = _messages;
      if (messages.isNotEmpty &&
          messages.last.role == ArkChatRole.assistant &&
          !messages.last.content.endsWith('（已停止生成）')) {
        final partial = messages.last.content.trim();
        messages[messages.length - 1] = messages.last.copyWith(
          content: partial.isEmpty ? '已停止生成。' : '$partial\n\n（已停止生成）',
        );
      }
      _state = AiConversationState.idle;
      _errorText = null;
      _isSynthesizing = false;
    });
  }

  Future<void> _executePendingPlan() async {
    final plan = _pendingPlan;
    if (plan == null || _executingTools) return;
    final messages = _conversationByModel[plan.model]!;
    setState(() {
      _pendingPlan = null;
      _executingTools = true;
      _lastToolResults = <InstrumentToolResult>[];
      _errorText = null;
    });

    var previousFailed = false;
    var duplicateRejected = false;
    var mutationEpoch = plan.mutationEpoch;
    final seenToolFingerprints = Set<String>.from(plan.seenToolFingerprints);
    final executedResults = <InstrumentToolResult>[];
    for (final call in plan.calls) {
      final InstrumentToolResult result;
      if (previousFailed) {
        result = InstrumentToolResult(
          callId: call.id,
          toolName: call.name,
          success: false,
          message: '前一步执行失败，本步骤已跳过',
          data: const <String, dynamic>{'skipped': true},
        );
      } else {
        final readOnly = widget.instrumentAgent.isReadOnly(call.name);
        final fingerprint = _toolFingerprint(
          call,
          readOnly: readOnly,
          mutationEpoch: mutationEpoch,
        );
        if (seenToolFingerprints.contains(fingerprint)) {
          duplicateRejected = true;
          result = InstrumentToolResult(
            callId: call.id,
            toolName: call.name,
            success: false,
            message: '检测到同一状态下的重复工具调用，已阻止循环执行',
            data: const <String, dynamic>{
              'duplicate_call_rejected': true,
              'instruction': '请使用已有工具结果直接总结，不要再次调用工具',
            },
          );
        } else {
          seenToolFingerprints.add(fingerprint);
          result = await widget.instrumentAgent.execute(call);
          if (result.success && !readOnly) mutationEpoch++;
        }
      }
      previousFailed = previousFailed || !result.success;
      executedResults.add(result);
      messages.add(
        ArkChatMessage(
          role: ArkChatRole.tool,
          content: jsonEncode(result.toJson()),
          toolCallId: result.callId,
        ),
      );
      if (!mounted) return;
      setState(() => _lastToolResults.add(result));
    }

    if (!mounted) return;
    setState(() => _executingTools = false);
    final terminalReply = _terminalToolReply(executedResults);
    if (terminalReply != null) {
      setState(() {
        messages.add(
          ArkChatMessage(role: ArkChatRole.assistant, content: terminalReply),
        );
        _state = AiConversationState.idle;
      });
      _scrollToBottom();
      if (_speechEnabled && _panelVisible) {
        unawaited(_speakAnswer(terminalReply));
      }
      return;
    }
    await _requestModelResponse(
      plan.model,
      toolRound: plan.toolRound + 1,
      seenToolFingerprints: seenToolFingerprints,
      mutationEpoch: mutationEpoch,
      allowTools: !duplicateRejected,
    );
  }

  String _latestUserRequest(List<ArkChatMessage> messages) {
    for (final message in messages.reversed) {
      if (message.role == ArkChatRole.user) return message.content;
    }
    return '';
  }

  String? _terminalToolReply(List<InstrumentToolResult> results) {
    for (final result in results) {
      if (_containsTerminalReason(result.data, 'no_signal_input') ||
          result.message.contains('未检测到信号输入') ||
          result.message.contains('CARRIER_NOT_FOUND')) {
        return '未检测到信号输入。';
      }
      if (_containsTerminalReason(
        result.data,
        'carrier_detection_timeout',
      )) {
        return result.data['running'] == true
            ? '载波检测尚未完成，相位噪声测量仍在后台进行；请稍后再次询问进度或结果。'
            : '载波检测尚未完成，暂时无法分析。';
      }
      if (_containsTerminalReason(
        result.data,
        'phase_noise_data_not_ready',
      )) {
        final pending = result.data['measurement_pending'] == true ||
            result.data['running'] == true;
        if (pending) {
          final received = result.data['received_points'];
          final planned = result.data['planned_total_points'];
          final progress = received is num && planned is num && planned > 0
              ? '（${received.toInt()}/${planned.toInt()} 点）'
              : '';
          return '相位噪声测量仍在后台进行$progress；请稍后再次询问，助手不会在本回合持续轮询。';
        }
        return '指定频偏暂时没有测量数据。';
      }
    }
    return null;
  }

  bool _containsTerminalReason(Object? value, String reason) {
    if (value is Map) {
      if (value['terminal_reason'] == reason) return true;
      return value.values.any(
        (entry) => _containsTerminalReason(entry, reason),
      );
    }
    if (value is Iterable) {
      return value.any((entry) => _containsTerminalReason(entry, reason));
    }
    return false;
  }

  Future<void> _cancelPendingPlan() async {
    final plan = _pendingPlan;
    if (plan == null) return;
    final messages = _conversationByModel[plan.model]!;
    final cancelledResults = plan.calls
        .map(
          (call) => InstrumentToolResult(
            callId: call.id,
            toolName: call.name,
            success: false,
            message: '用户取消了本次仪器操作',
            data: const <String, dynamic>{'cancelled': true},
          ),
        )
        .toList();
    for (final result in cancelledResults) {
      messages.add(
        ArkChatMessage(
          role: ArkChatRole.tool,
          content: jsonEncode(result.toJson()),
          toolCallId: result.callId,
        ),
      );
    }
    setState(() {
      _pendingPlan = null;
      _lastToolResults = cancelledResults;
    });
    await _requestModelResponse(
      plan.model,
      toolRound: plan.toolRound + 1,
      seenToolFingerprints: plan.seenToolFingerprints,
      mutationEpoch: plan.mutationEpoch,
      allowTools: false,
    );
  }

  String _toolFingerprint(
    InstrumentToolCall call, {
    required bool readOnly,
    required int mutationEpoch,
  }) {
    final scope = readOnly ? 'read@$mutationEpoch' : 'mutation';
    return '$scope:${call.name}:${jsonEncode(_canonicalJson(call.arguments))}';
  }

  dynamic _canonicalJson(dynamic value) {
    if (value is Map) {
      final keys = value.keys.map((key) => key.toString()).toList()..sort();
      return <String, dynamic>{
        for (final key in keys) key: _canonicalJson(value[key]),
      };
    }
    if (value is List) return value.map(_canonicalJson).toList();
    return value;
  }

  Future<void> _abortAsrSession() async {
    _resultTimeout?.cancel();
    await _audioSubscription?.cancel();
    _audioSubscription = null;
    if (await _recorder.isRecording()) await _recorder.stop();
    await _asrClient.close();
    _pendingBytes.clear();
    _heldFrame = null;
    widget.onListeningChanged(false);
  }

  void _clearConversation() {
    _modelRequestGeneration++;
    _arkClient.cancelActiveRequest();
    _ttsGeneration++;
    unawaited(_ttsPlayer.stop());
    setState(() {
      _messages.clear();
      _responseModelIds.remove(_selectedModel);
      _liveTranscript = '';
      _textController.clear();
      _state = AiConversationState.idle;
      _errorText = null;
      _isSynthesizing = false;
      _pendingPlan = null;
      _lastToolResults = <InstrumentToolResult>[];
    });
  }

  void _switchModel(ArkModel model) {
    if (model == _selectedModel) return;
    _ttsGeneration++;
    unawaited(_ttsPlayer.stop());
    _textController.clear();
    setState(() {
      _selectedModel = model;
      _liveTranscript = '';
      _state = AiConversationState.idle;
      _errorText = null;
      _isSynthesizing = false;
      _pendingPlan = null;
      _lastToolResults = <InstrumentToolResult>[];
    });
    _scrollToBottom();
  }

  void _switchAgentMode(InstrumentAgentMode mode) {
    if (mode == _agentMode || _isBusy || isListening) return;
    setState(() {
      _agentMode = mode;
      _errorText = null;
      _lastToolResults = <InstrumentToolResult>[];
    });
  }

  void _submitTypedText(String _) {
    if (_isBusy || _state == AiConversationState.listening) return;
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    _textFocusNode.unfocus();
    unawaited(_sendToModel(text));
  }

  Future<void> _toggleSpeech(bool enabled) async {
    if (!enabled) {
      _ttsGeneration++;
      setState(() {
        _speechEnabled = false;
        _isSynthesizing = false;
      });
      await _ttsPlayer.stop();
      return;
    }
    if (!VolcengineTtsConfig.isConfigured) {
      _showError('请先配置豆包语音 API Key；ASR 与 TTS 可以共用同一个 Key');
      return;
    }
    setState(() {
      _speechEnabled = true;
      _errorText = null;
      if (_state == AiConversationState.error) {
        _state = AiConversationState.idle;
      }
    });
  }

  Future<void> _speakAnswer(String text) async {
    final generation = ++_ttsGeneration;
    await _ttsPlayer.stop();
    if (!mounted || generation != _ttsGeneration || !_speechEnabled) return;
    setState(() => _isSynthesizing = true);
    try {
      final audio = await _ttsClient.synthesize(text);
      if (!mounted || generation != _ttsGeneration || !_speechEnabled) return;
      await _ttsPlayer.play(audio);
      if (mounted && generation == _ttsGeneration) {
        setState(() => _isSynthesizing = false);
      }
    } catch (error) {
      if (!mounted || generation != _ttsGeneration) return;
      setState(() {
        _isSynthesizing = false;
        _errorText = _friendlyError(error);
      });
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    setState(() {
      _state = AiConversationState.error;
      _errorText = message;
    });
  }

  String _friendlyError(Object error) {
    if (error is VolcengineTtsException) {
      return switch (error.statusCode) {
        401 => '语音播报鉴权失败，请检查豆包语音 API Key',
        403 => '语音播报无调用权限，请先开通豆包语音合成模型 2.0',
        429 => '语音生成请求过于频繁或额度不足，请稍后重试',
        _ =>
          '语音播报失败${error.code == null ? '' : '（${error.code}）'}：${error.message}',
      };
    }
    if (error is ArkApiException) {
      return switch (error.statusCode) {
        401 => '方舟鉴权失败，请检查方舟 API Key',
        403 => '无权调用该模型，请先在方舟“开通管理”中开通模型',
        404 => '未找到模型，请确认模型已开通且模型 ID 有效',
        429 => '方舟请求过于频繁或额度不足，请稍后重试并检查用量',
        _ => '方舟请求失败：${error.message}',
      };
    }
    if (error is FormatException) {
      return '模型返回的工具参数不完整，本轮未执行该工具；请重试当前操作';
    }
    final text = error.toString();
    if (text.contains('401') || text.contains('403')) {
      return '鉴权失败，请检查对应 API Key 和服务是否已开通';
    }
    if (error is TimeoutException) return '请求超时，请检查网络后重试';
    return text.replaceFirst('Bad state: ', '').replaceFirst('Exception: ', '');
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_chatScrollController.hasClients) return;
      _chatScrollController.jumpTo(
        _chatScrollController.position.maxScrollExtent,
      );
    });
  }

  String get _statusText {
    if (_executingTools) return '正在执行仪器操作并等待 ACK…';
    if (_pendingPlan != null) return '操作计划等待确认';
    return switch (_state) {
      AiConversationState.idle => _messages.isEmpty ? '可以说出或输入你的问题' : '可以继续提问',
      AiConversationState.connecting => '正在连接豆包 ASR 2.0…',
      AiConversationState.listening => '正在聆听，再次点击 AI 或停止按钮即可发送',
      AiConversationState.recognizing => '正在整理最终识别结果…',
      AiConversationState.thinking => '${_selectedModel.displayName} 正在回答…',
      AiConversationState.error => '出现问题，请检查提示后重试',
    };
  }

  Color get _stateColor {
    if (_executingTools) return _accent;
    if (_pendingPlan != null) return const Color(0xFFFFC857);
    return switch (_state) {
      AiConversationState.listening => _recording,
      AiConversationState.error => const Color(0xFFFF7B72),
      AiConversationState.connecting ||
      AiConversationState.recognizing ||
      AiConversationState.thinking =>
        _accent,
      AiConversationState.idle => const Color(0xFF5BD69A),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(
        color: _surface,
        border: Border(left: BorderSide(color: _border)),
      ),
      child: Column(
        children: <Widget>[
          _buildHeader(),
          _buildModelBar(),
          if (!VolcengineAsrConfig.isConfigured || !ArkConfig.isConfigured)
            _buildConfigBanner(),
          Expanded(child: _buildConversation()),
          if (_pendingPlan != null ||
              _executingTools ||
              _lastToolResults.isNotEmpty)
            _buildAgentActivityPanel(),
          _buildFooter(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final disabled = _isBusy || _state == AiConversationState.listening;
    return Container(
      height: 66,
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _border)),
      ),
      child: Row(
        children: <Widget>[
          _buildAssistantMark(size: 34),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'AI 仪器助手',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 3),
                Row(
                  children: <Widget>[
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: _stateColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _statusText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10,
                          color: _mutedText,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (_isSynthesizing)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 5),
              child: SizedBox(width: 15, height: 15, child: ProgressRing()),
            ),
          Tooltip(
            message: _speechEnabled ? '关闭语音播报' : '开启语音播报',
            child: IconButton(
              icon: Icon(
                _speechEnabled
                    ? material.Icons.volume_up_rounded
                    : material.Icons.volume_off_rounded,
                size: 18,
                color: _speechEnabled ? _accent : _mutedText,
              ),
              onPressed: () => unawaited(_toggleSpeech(!_speechEnabled)),
            ),
          ),
          Tooltip(
            message: '清空当前模型的对话',
            child: IconButton(
              icon: const Icon(material.Icons.delete_outline_rounded, size: 18),
              onPressed: disabled ? null : _clearConversation,
            ),
          ),
          Tooltip(
            message: '关闭面板（保留聊天记录）',
            child: IconButton(
              icon: const Icon(material.Icons.close_rounded, size: 18),
              onPressed: widget.onClose,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModelBar() {
    final disabled = _isBusy || _state == AiConversationState.listening;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 8),
      decoration: const BoxDecoration(
        color: Color(0xFF202329),
        border: Border(bottom: BorderSide(color: _border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Text('模型', style: TextStyle(fontSize: 12)),
              const SizedBox(width: 10),
              Expanded(
                child: ComboBox<ArkModel>(
                  value: _selectedModel,
                  isExpanded: true,
                  items: ArkModel.values
                      .map(
                        (model) => ComboBoxItem<ArkModel>(
                          value: model,
                          child: Text(
                            model.displayName,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: disabled
                      ? null
                      : (model) {
                          if (model != null) _switchModel(model);
                        },
                ),
              ),
              const SizedBox(width: 4),
              Tooltip(
                message:
                    '${_selectedModel.description}\n请求模型：${_selectedModel.modelId}'
                    '${_lastResponseModelId == null ? '' : '\nAPI 返回：$_lastResponseModelId'}',
                child: const Icon(
                  material.Icons.info_outline_rounded,
                  size: 17,
                  color: _mutedText,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            _lastResponseModelId == null
                ? '请求 ID：${_selectedModel.modelId}'
                : 'API 返回：$_lastResponseModelId',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              color: _lastResponseModelId == null
                  ? _mutedText
                  : const Color(0xFF5BD69A),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              const Text('模式', style: TextStyle(fontSize: 12)),
              const SizedBox(width: 10),
              Expanded(
                child: Tooltip(
                  message: _agentMode.description,
                  child: ComboBox<InstrumentAgentMode>(
                    value: _agentMode,
                    isExpanded: true,
                    items: InstrumentAgentMode.values
                        .map(
                          (mode) => ComboBoxItem<InstrumentAgentMode>(
                            value: mode,
                            child: Text('${mode.label} · ${mode.description}'),
                          ),
                        )
                        .toList(),
                    onChanged: disabled
                        ? null
                        : (mode) {
                            if (mode != null) _switchAgentMode(mode);
                          },
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAgentActivityPanel() {
    final plan = _pendingPlan;
    return Container(
      constraints: const BoxConstraints(maxHeight: 230),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: const BoxDecoration(
        color: Color(0xFF202329),
        border: Border(top: BorderSide(color: _border)),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  _executingTools
                      ? material.Icons.sync_rounded
                      : plan != null
                          ? material.Icons.fact_check_outlined
                          : material.Icons.task_alt_rounded,
                  size: 17,
                  color: _executingTools
                      ? _accent
                      : plan != null
                          ? const Color(0xFFFFC857)
                          : const Color(0xFF5BD69A),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    _executingTools
                        ? '正在执行工具并等待设备确认'
                        : plan != null
                            ? '仪器操作计划'
                            : '最近一次执行结果',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            if (plan != null) ...<Widget>[
              const SizedBox(height: 8),
              ...plan.calls.indexed.map(
                (entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      SizedBox(
                        width: 22,
                        child: Text(
                          '${entry.$1 + 1}.',
                          style: const TextStyle(
                            color: _mutedText,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          widget.instrumentAgent.describeCall(entry.$2),
                          style: const TextStyle(fontSize: 11, height: 1.35),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 5),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  Button(
                    onPressed: () => unawaited(_cancelPendingPlan()),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => unawaited(_executePendingPlan()),
                    child: Text(
                      _agentMode == InstrumentAgentMode.agent
                          ? '确认计划并执行'
                          : '确认本批操作',
                    ),
                  ),
                ],
              ),
            ],
            if (_lastToolResults.isNotEmpty) ...<Widget>[
              if (plan != null) const Divider(size: 16),
              ..._lastToolResults.map(
                (result) => Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Icon(
                        result.success
                            ? material.Icons.check_circle_outline_rounded
                            : material.Icons.error_outline_rounded,
                        size: 15,
                        color: result.success
                            ? const Color(0xFF5BD69A)
                            : const Color(0xFFFF7B72),
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          '${result.toolName}：${result.message}',
                          style: const TextStyle(fontSize: 11, height: 1.35),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAssistantMark({required double size}) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[Color(0xFF6D8DFF), Color(0xFF8C5DFF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        shape: BoxShape.circle,
      ),
      child: Icon(
        material.Icons.auto_awesome_rounded,
        size: size * 0.52,
        color: Colors.white,
      ),
    );
  }

  Widget _buildConfigBanner() {
    final missing = <String>[
      if (!VolcengineAsrConfig.isConfigured) '豆包语音 Key',
      if (!ArkConfig.isConfigured) '方舟 Key',
    ].join('、');
    return Container(
      width: double.infinity,
      color: const Color(0xFF493A1D),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        '尚未配置：$missing。请在对应 config.dart 文件中填写。',
        style: const TextStyle(color: Color(0xFFFFD58A), fontSize: 12),
      ),
    );
  }

  Widget _buildConversation() {
    final visibleMessages =
        _messages.where((message) => message.role != ArkChatRole.tool).toList();
    final showLiveTranscript = _liveTranscript.isNotEmpty &&
        (_state == AiConversationState.listening ||
            _state == AiConversationState.recognizing);
    if (visibleMessages.isEmpty && !showLiveTranscript) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              material.Icons.graphic_eq_rounded,
              size: 38,
              color: _mutedText,
            ),
            const SizedBox(height: 10),
            const Text(
              '说出或输入你的问题',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 5),
            Text(
              _agentMode == InstrumentAgentMode.chat
                  ? '问答模式不会控制仪器'
                  : _agentMode == InstrumentAgentMode.assisted
                      ? '可查询配置并生成需要确认的仪器操作计划'
                      : 'Agent 模式会自动执行工具计划，请明确描述目标',
              style: const TextStyle(color: _mutedText, fontSize: 12),
            ),
          ],
        ),
      );
    }

    final itemCount = visibleMessages.length + (showLiveTranscript ? 1 : 0);
    return ListView.separated(
      controller: _chatScrollController,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
      itemCount: itemCount,
      separatorBuilder: (_, __) => const SizedBox(height: 14),
      itemBuilder: (context, index) {
        if (index < visibleMessages.length) {
          final message = visibleMessages[index];
          final thinking = _state == AiConversationState.thinking &&
              index == visibleMessages.length - 1 &&
              message.content.isEmpty;
          return _buildMessage(message, thinking: thinking);
        }
        return _buildLiveTranscript();
      },
    );
  }

  Widget _buildMessage(ArkChatMessage message, {required bool thinking}) {
    final isUser = message.role == ArkChatRole.user;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (!isUser) ...<Widget>[
            _buildAssistantMark(size: 28),
            const SizedBox(width: 9),
          ],
          Flexible(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 720),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isUser ? const Color(0xFF284D78) : _surfaceElevated,
                borderRadius: BorderRadius.circular(13),
                border: Border.all(
                  color: isUser ? const Color(0xFF3D6EAA) : _border,
                ),
              ),
              child: thinking
                  ? const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        SizedBox(width: 15, height: 15, child: ProgressRing()),
                        SizedBox(width: 9),
                        Text('正在思考…', style: TextStyle(color: _mutedText)),
                      ],
                    )
                  : SelectionArea(
                      child: Text(
                        message.content,
                        style: const TextStyle(fontSize: 14, height: 1.45),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveTranscript() {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 720),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: _surfaceMuted,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: _recording.withValues(alpha: 0.75)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              '实时识别',
              style: TextStyle(color: Color(0xFFFFA3A6), fontSize: 11),
            ),
            const SizedBox(height: 4),
            Text(_liveTranscript, style: const TextStyle(fontSize: 14)),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter() {
    final listening = _state == AiConversationState.listening;
    final canStopThinking = _state == AiConversationState.thinking;
    final canSend =
        !_isBusy && !listening && _textController.text.trim().isNotEmpty;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
      decoration: const BoxDecoration(
        color: Color(0xFF202329),
        border: Border(top: BorderSide(color: _border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (_errorText != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(
                children: <Widget>[
                  const Icon(
                    material.Icons.error_outline_rounded,
                    size: 15,
                    color: Color(0xFFFF7B72),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      _errorText!,
                      style: const TextStyle(
                        color: Color(0xFFFF9B94),
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Container(
            height: 62,
            padding: const EdgeInsets.fromLTRB(15, 6, 6, 6),
            decoration: BoxDecoration(
              color: _surfaceElevated,
              borderRadius: BorderRadius.circular(31),
              border: Border.all(color: _border),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 16,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: TextBox(
                    controller: _textController,
                    focusNode: _textFocusNode,
                    readOnly: _isBusy || listening,
                    placeholder: listening
                        ? '正在接收语音…'
                        : _state == AiConversationState.thinking
                            ? '请等待本轮回答完成'
                            : '输入问题，按回车发送',
                    onChanged: (_) => setState(() {}),
                    onSubmitted: _submitTypedText,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: const WidgetStatePropertyAll<BoxDecoration>(
                      BoxDecoration(
                        color: Colors.transparent,
                        border: Border.fromBorderSide(BorderSide.none),
                        borderRadius: BorderRadius.zero,
                      ),
                    ),
                    foregroundDecoration:
                        const WidgetStatePropertyAll<BoxDecoration>(
                      BoxDecoration(
                        color: Colors.transparent,
                        border: Border.fromBorderSide(BorderSide.none),
                        borderRadius: BorderRadius.zero,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Tooltip(
                  message: canStopThinking ? '终止思考' : '发送文本',
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: Button(
                      onPressed: canStopThinking
                          ? () => unawaited(_stopThinking())
                          : canSend
                              ? () => _submitTypedText(_textController.text)
                              : null,
                      style: ButtonStyle(
                        shape: const WidgetStatePropertyAll<ShapeBorder>(
                          CircleBorder(),
                        ),
                        backgroundColor: WidgetStatePropertyAll<Color>(
                          canStopThinking
                              ? _recording
                              : canSend
                                  ? _accent
                                  : _surfaceMuted,
                        ),
                        padding:
                            const WidgetStatePropertyAll<EdgeInsetsGeometry>(
                          EdgeInsets.zero,
                        ),
                      ),
                      child: Icon(
                        canStopThinking
                            ? material.Icons.stop_rounded
                            : material.Icons.arrow_upward_rounded,
                        size: 20,
                        color: canStopThinking || canSend
                            ? Colors.white
                            : _mutedText,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                _buildRecordingButton(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordingButton() {
    final listening = _state == AiConversationState.listening;
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final glow = listening ? 4 + _pulseController.value * 7 : 0.0;
        return Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: listening
                ? <BoxShadow>[
                    BoxShadow(
                      color: _recording.withValues(alpha: 0.45),
                      blurRadius: glow,
                      spreadRadius: _pulseController.value * 2,
                    ),
                  ]
                : null,
          ),
          child: child,
        );
      },
      child: Tooltip(
        message: listening ? '结束录音并发送' : '开始录音',
        child: SizedBox(
          width: 48,
          height: 48,
          child: Button(
            onPressed: _isBusy ? null : _toggleRecording,
            style: ButtonStyle(
              shape: const WidgetStatePropertyAll<ShapeBorder>(CircleBorder()),
              backgroundColor: WidgetStatePropertyAll<Color>(
                listening ? _recording : const Color(0xFF3A3F48),
              ),
              padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
                EdgeInsets.zero,
              ),
            ),
            child: Icon(
              listening
                  ? material.Icons.stop_rounded
                  : material.Icons.mic_rounded,
              size: 23,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class _PendingInstrumentPlan {
  const _PendingInstrumentPlan({
    required this.model,
    required this.calls,
    required this.toolRound,
    required this.seenToolFingerprints,
    required this.mutationEpoch,
  });

  final ArkModel model;
  final List<InstrumentToolCall> calls;
  final int toolRound;
  final Set<String> seenToolFingerprints;
  final int mutationEpoch;
}

class _ToolCallAccumulator {
  String _id = '';
  String _name = '';
  final StringBuffer _arguments = StringBuffer();

  void add(ArkToolCallDelta delta) {
    if (delta.id != null && delta.id!.isNotEmpty) _id = delta.id!;
    if (delta.name != null && delta.name!.isNotEmpty) _name = delta.name!;
    _arguments.write(delta.argumentsFragment);
  }

  ArkToolCallData build() {
    if (_id.isEmpty || _name.isEmpty) {
      throw const FormatException('模型返回了不完整的工具调用');
    }
    final arguments = ArkChatClient.parseToolArguments(_arguments.toString());
    return ArkToolCallData(
      id: _id,
      name: _name,
      arguments: arguments,
    );
  }
}
