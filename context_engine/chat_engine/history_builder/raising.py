from typing import Tuple

from context_engine.chat_engine.history_builder.base import BaseHistoryBuilder
from context_engine.models.data_models import Messages


class RaisingHistoryBuilder(BaseHistoryBuilder):

    def build(self,
              history: Messages,
              max_tokens: int) -> Tuple[Messages, int]:
        token_count = self._tokenizer.messages_token_count(history)
        if token_count > max_tokens:
            raise ValueError(f"The history require {token_count} tokens, "
                             f"which exceeds the calculated limit for history "
                             f"of {max_tokens} tokens.")
        return history, token_count

    async def abuild(self,
                     full_history: Messages,
                     max_tokens: int) -> Tuple[Messages, int]:
        raise NotImplementedError
