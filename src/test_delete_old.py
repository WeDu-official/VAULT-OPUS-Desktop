import asyncio
import os
import sqlite3
from database import DatabaseManager

file_table_columns = [
    'base_filename', 'part_number', 'total_parts',
    'message_id', 'channel_id', 'relative_path_in_archive', 'root_upload_name', 'upload_timestamp',
    'is_nicknamed', 'original_base_filename', 'is_base_filename_nicknamed',
    'encryption_mode', 'encryption_key_auto', 'password_seed_hash',
    'store_hash_flag', 'version', 'itemid', 'raw_chunk_size', 'chunkhash'
]

class MockLog:
    def info(self, msg): pass
    def warning(self, msg): print("[WARN]", msg)
    def error(self, msg): print("[ERROR]", msg)
    def debug(self, msg): pass

async def main():
    db_file = 'test_old.db'
    if os.path.exists(db_file):
        os.remove(db_file)
    
    db = DatabaseManager(file_table_columns, MockLog())
    
    # Create an old schema table WITHOUT itemid
    conn = sqlite3.connect(db_file)
    conn.execute("CREATE TABLE file_metadata_table (base_filename TEXT, version TEXT)")
    conn.execute("INSERT INTO file_metadata_table (base_filename, version) VALUES ('myfolder', '0.0.0.1')")
    conn.commit()
    conn.close()
    
    # Reading will auto-migrate and add itemid as NULL
    entries = await db._db_read_sync(db_file, {})
    print('Entries before delete:', len(entries))
    print('itemid value:', repr(entries[0].get('itemid')))
    print('part_number value:', repr(entries[0].get('part_number')))
    
    # Attempt delete exactly how delete_manager does
    target = {
        'root_upload_name': entries[0].get('root_upload_name'),
        'relative_path_in_archive': entries[0].get('relative_path_in_archive'),
        'base_filename': entries[0].get('base_filename'),
        'version': entries[0].get('version'),
        'part_number': entries[0].get('part_number', 0),
        'itemid': entries[0].get('itemid')
    }
    
    deleted_count = await db._db_delete_sync(db_file, [target])
    print('Deleted count:', deleted_count)
    
    entries_after = await db._db_read_sync(db_file, {})
    print('Entries after delete:', len(entries_after))

asyncio.run(main())
