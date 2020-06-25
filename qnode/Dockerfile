FROM python:3-slim

ARG REQUIREMENTS_TXT=requirements.txt

ENV PYTHONUSERBASE="/service"
WORKDIR /service
COPY $REQUIREMENTS_TXT .

RUN \
    pip3 install --upgrade pip && \
    pip3 install --user -r $REQUIREMENTS_TXT

# Add apt-get install build-essential && gcc if we need c deps
COPY qnodeinit.py /service/
ENV PYTHONPATH="/service"
ENV PATH="/service/bin:$PATH"
# ENTRYPOINT ["/usr/local/bin/python3.8"]
CMD ["python3", "qnodeinit.py", "--forever", "--nodedir", "/var/lib/quorum"]
# CMD ["python3", "-c", "import time; while True: print('sleep...'); time.sleep(5)"]
