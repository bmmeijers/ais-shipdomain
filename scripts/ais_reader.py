#!/usr/bin/env python3
from functools import reduce

import glob
import sys

# Run from a terminal:
#
# python3 ais_reader.py | psql -d <database>

# FIXME:
# - update seconds to second of NMEA payload???


ASCII = ['@', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '[', '/', ']', '^', '_', ' ', '!', '"', '#', '$', '%', '&', '/', '(', ')', '*', '+', ',', '-', '.', '/', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', ':', ';', '<', '=', '>', '?']

SIXBIT = {i: c for c, i in zip(ASCII, range(64))}

TO_SIXBIT = {'0': '000000',
             '1': '000001',
             '2': '000010',
             '3': '000011',
             '4': '000100',
             '5': '000101',
             '6': '000110',
             '7': '000111',
             '8': '001000',
             '9': '001001',
             ':': '001010',
             ';': '001011',
             '<': '001100',
             '=': '001101',
             '>': '001110',
             '?': '001111',
             '@': '010000',
             'A': '010001',
             'B': '010010',
             'C': '010011',
             'D': '010100',
             'E': '010101',
             'F': '010110',
             'G': '010111',
             'H': '011000',
             'I': '011001',
             'J': '011010',
             'K': '011011',
             'L': '011100',
             'M': '011101',
             'N': '011110',
             'O': '011111',
             'P': '100000',
             'Q': '100001',
             'R': '100010',
             'S': '100011',
             'T': '100100',
             'U': '100101',
             'V': '100110',
             'W': '100111',
             '`': '101000',
             'a': '101001',
             'b': '101010',
             'c': '101011',
             'd': '101100',
             'e': '101101',
             'f': '101110',
             'g': '101111',
             'h': '110000',
             'i': '110001',
             'j': '110010',
             'k': '110011',
             'l': '110100',
             'm': '110101',
             'n': '110110',
             'o': '110111',
             'p': '111000',
             'q': '111001',
             'r': '111010',
             's': '111011',
             't': '111100',
             'u': '111101',
             'v': '111110',
             'w': '111111'
             }

SEP = "~"


def to_sixbit(raw):
    return ''.join(TO_SIXBIT[c] for c in raw)


def as_int(binary_payload, start, end):
    return int(binary_payload[start:end], 2)


def as_coord(binary_payload, start, end):
    delta = end - start 
    assert (delta == 27) or (delta == 28)
    c = as_int(binary_payload, start, end)
    if c & pow(2, delta-1) > 0: # negative, iff coordinate has signed bit on delta position 27/28
        c = -(pow(2, delta) - c) # FIXME: check whether this lead to correct negative coordinate?
    return round(c / 600_000., 5)


def as_txt(binary_payload, start, end):
    text = ''.join(SIXBIT[int(binary_payload[i:i + 6], 2)] for i in range(start, end, 6)) 
    if '@' in text:
        # when @ occurs, the rest of the string should be ignored
        text = text[:text.index('@')]
    return text.rstrip()


mapping123 = [
    (None, 'ts', None, None, 'timestamp with time zone'),
    (as_int, 'type', 0, 6, 'int'),
    (as_int, 'repeat', 6, 8, 'int'),
    (as_int, 'mmsi', 8, 38, 'int'),
    (as_int, 'status', 38, 42, 'int'),
    (as_int, 'turn', 42, 50, 'int'),
    (as_int, 'speed', 50, 60, 'int'), # integer 1022 -> 102.2 knots, 1023 -> speed not avaiblable (0.1 knot resolution
    (as_int, 'accuracy', 60, 61, 'int'),
    (as_coord, 'longitude', 61, 89, 'real'),
    (as_coord, 'latitude', 89, 116, 'real'),
    (as_int, 'course', 116, 128, 'int'),
    (as_int, 'heading', 128, 137, 'int'),
    (as_int, 'second', 137, 143, 'int'),
    (as_int, 'maneuvre', 143,145 , 'int'),
    # skip 145-148
    (as_int, 'raim', 148, 149, 'int'),
    (as_int, 'radio', 149, 168, 'int'),
]
names123 = [item[1] for item in mapping123]
names_dbtypes_123 = [(item[1], item[4]) for item in mapping123]


mapping5 = [
    (None, 'ts', None, None, 'timestamp with time zone'),
    (as_int, 'type', 0, 6, 'int'),
    (as_int, 'repeat', 6, 8, 'int'),
    (as_int, 'mmsi', 8, 38, 'int'),
    (as_int, 'ais_version', 38, 40, 'int'),
    (as_int, 'imo', 40, 70, 'int'),
    (as_txt, 'callsign', 70, 112, 'text'),
    (as_txt, 'shipname', 112, 232, 'text'),
    (as_int, 'shiptype', 232, 240, 'int'),
    (as_int, 'to_bow', 240, 249, 'int'),
    (as_int, 'to_stern', 249, 258, 'int'),
    (as_int, 'to_port', 258, 264, 'int'),
    (as_int, 'to_starboard', 264, 270, 'int'),
    (as_int, 'epfd', 270, 274, 'int'),
    (as_int, 'month', 274, 278, 'int'),
    (as_int, 'day', 278, 283, 'int'),
    (as_int, 'hour', 283, 288, 'int'),
    (as_int, 'minute', 288, 294, 'int'),
    (as_int, 'draught', 294, 302, 'int'),
    (as_txt, 'destination', 302, 422, 'text'),
    (as_int, 'dte', 422, 423, 'int'),
]
names5 = [item[1] for item in mapping5]
names_dbtypes_5 = [(item[1], item[4]) for item in mapping5]


def as_type_and_sixbit(payload):
    raw_bits = to_sixbit(payload)
    type_ = int(raw_bits[:6], 2)
    return (type_, raw_bits)


def decode_payload_dynamic(binary_payload, type_, timestamp):
    out = {'ts': timestamp}
    for fn, name, start, end, db_type in mapping123:
        if fn is not None:
            out[name] = fn(binary_payload, start, end)
    return SEP.join(map(str, (out[name] for name in names123)))


def decode_payload_static(binary_payload, type_, timestamp):
    assert type_ in (5,)
    out = {'ts': timestamp}
    for fn, name, start, end, db_type in mapping5:
        if fn is not None:
            out[name] = fn(binary_payload, start, end)
    return SEP.join(map(str, (out[name] for name in names5)))


def decode_message(payload, timestamp, static):
    tp, sixbit = as_type_and_sixbit(payload)
    if tp in (1, 2, 3) and not static:
        print(decode_payload_dynamic(sixbit, tp, timestamp))
    elif tp in (5,) and static:
        print(decode_payload_static(sixbit, tp, timestamp))


def integrity(to_check, checksum):
    return hex(reduce((lambda x, y: x ^ y), [ord(c) for c in to_check]))[2:].upper() == checksum


def prepare_tables(table_nm_dynamic, table_nm_static, static):
    print("\\timing on")
    if not static:
        # Set up table for dynamic messages
        print("DROP TABLE IF EXISTS {};".format(table_nm_dynamic))

        fields = ", ".join(["{} {}".format(column_name, column_type) for column_name, column_type in names_dbtypes_123])
        print("CREATE TABLE {}({});".format(table_nm_dynamic, fields))
    else:
        # Set up table for static messages
        print("DROP TABLE IF EXISTS {};".format(table_nm_static))

        fields = ", ".join(["{} {}".format(column_name, column_type) for column_name, column_type in names_dbtypes_5])
        print("CREATE TABLE {}({});".format(table_nm_static, fields))


def post_load(table_nm_dynamic, table_nm_static):
    geom_column = 'wkb_geom'

    # dynamic table indexes
    sql = "alter table {} add column {} geometry(point, 4326);".format(table_nm_dynamic, geom_column)
    print(sql)

    sql = "update {0} set {1} = st_setsrid(st_makepoint(longitude, latitude),4326);".format(table_nm_dynamic, geom_column)
    print(sql)

    sql = "create index {0}__{1}__idx on {0} using gist(wkb_geom) tablespace indx;".format(table_nm_dynamic, geom_column)
    print(sql)

    sql = "create index {0}__{1}__idx on {0} ({1}) tablespace indx;".format(table_nm_dynamic, 'mmsi')
    print(sql)

    sql = "create index {0}__{1}__idx on {0} ({1}) tablespace indx;".format(table_nm_dynamic, 'ts')
    print(sql)

    # static table indexes
    sql = "create index {0}__{1}__idx on {0} ({1}) tablespace indx;".format(table_nm_static, 'mmsi')
    print(sql)

    sql = "create index {0}__{1}__idx on {0} ({1}) tablespace indx;".format(table_nm_static, 'ts')
    print(sql)

    # vacuum dynamic + static table indexes
    sql = "vacuum analyze {0};".format(table_nm_dynamic)
    print(sql)
    sql = "vacuum analyze {0};".format(table_nm_static)
    print(sql)


def parse_data(log_file_nm, table_nm_dynamic, table_nm_static, static):

    if not static:
        fields = ", ".join(["{}".format(column_name) for column_name, column_type in names_dbtypes_123])
        print("COPY {}({}) FROM STDIN DELIMITER E'{}';".format(table_nm_dynamic, fields, SEP))
    else:
        fields = ", ".join(["{}".format(column_name) for column_name, column_type in names_dbtypes_5])
        print("COPY {}({}) FROM STDIN DELIMITER E'{}';".format(table_nm_static, fields, SEP))

    with open(log_file_nm, 'r') as file:
        queue = {}
        for sentence in file:
            if sentence.startswith('$GP'):
                #$--ZDA,hhmmss.ss,xx,xx,xxxx,xx,xx
                #hhmmss.ss = UTC
                #xx = Day, 01 to 31
                #xx = Month, 01 to 12
                #xxxx = Year
                #xx = Local zone description, 00 to +/- 13 hours
                #xx = Local zone minutes description (same sign as hours) 
                split_sentence = sentence.strip().split(',')
                hhmmss = split_sentence[1]
                hh, mm, ss = hhmmss[0:2], hhmmss[2:4], hhmmss[4:6]
                day = split_sentence[2]
                month = split_sentence[3]
                year = split_sentence[4]
                zone = split_sentence[5]
                check = split_sentence[6]

                # 2018-11-11T12:07:22.3+05:00
                timestamp = f'{year}-{month}-{day}T{hh}:{mm}:{ss}+00:00'

            elif sentence.startswith('!AI'):
                split_sentence = sentence.strip().split(',')
                message_type, count, number, sequence_id, channel_code, payload, fill_bits = split_sentence
                # If the message is multi-line, we need more sentences for full payload
                if int(count) > 1:
                    # If the current id is already in the queue
                    if sequence_id in queue:

                        # If the current message is the last message of the sequence
                        # we have collected the full payload 
                        if number == queue[sequence_id][1]:

                            # Join the payload, delete the id from queue, decode full payload and continue
                            payload = queue[sequence_id][0] + payload
                            del queue[sequence_id]
                            decode_message(payload, timestamp, static)
                            continue

                        # If this is not yet the last message of the sequence
                        else:
                            # Join the payload, remember payload so far and continue
                            queue[sequence_id] = queue[sequence_id][0] + payload, count
                            continue

                    # If the id is not yet in the queue
                    else:
                        queue[sequence_id] = payload, count
                        continue

                # If the message is not multi-line we can just decode it
                else:
                    decode_message(payload, timestamp, static)

    print('\\.')


def main():
    path = '*.txt'
    ## static = True or False
    ## False: parse position reports (message type 1|2|3), True: parse voyage reports (message type 5)
    tbl_dynamic = 'ais_logs_dynamic'
    tbl_static =  'ais_logs_static'

    # create schema
    prepare_tables(tbl_dynamic, tbl_static, True)
    prepare_tables(tbl_dynamic, tbl_static, False)

    # data load
    for log in sorted(glob.glob(path)):
        parse_data(log, tbl_dynamic, tbl_static, True)
        parse_data(log, tbl_dynamic, tbl_static, False)

    # post load: indexes + vacuum
    post_load(tbl_dynamic, tbl_static)



if __name__ == '__main__':
    main()
