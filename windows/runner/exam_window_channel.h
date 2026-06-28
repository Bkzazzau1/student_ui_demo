#ifndef RUNNER_EXAM_WINDOW_CHANNEL_H_
#define RUNNER_EXAM_WINDOW_CHANNEL_H_

#include <flutter/binary_messenger.h>
#include <windows.h>

void RegisterExamWindowChannel(flutter::BinaryMessenger* messenger, HWND window);
bool ExamWindowHandleMessage(UINT message, WPARAM wparam);
bool ExamWindowIsActive();

#endif
