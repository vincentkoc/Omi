import getPublicMemories from '@/src/actions/memories/get-public-memories';
import MemoryItem from './memory-item';

export default async function MemoryList() {
  const memories = await getPublicMemories();
  return (
    <div className="text-white">
      <div className="flex flex-col gap-5">
        {memories.map((memory) => (
          <MemoryItem key={memory.id} memory={memory} />
        ))}
      </div>
    </div>
  );
}
