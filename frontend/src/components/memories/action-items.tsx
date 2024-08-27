import { ActionItems as ActionItemsType } from '@/src/types/memory.types';
import { CheckCircle } from 'iconoir-react';

interface ActionsItemsProps {
  items: ActionItemsType[];
}

export default function ActionItems({ items }: ActionsItemsProps) {
  return (
    <div>
      <h3 className="text-2xl font-semibold">Action Items</h3>
      <ul className="mt-3">
        {items.map((item, index) => (
          <li key={index} className="my-5 flex gap-3 items-start">
            {item.completed ? (
              <div className='mt-1'>
                <CheckCircle className="min-w-min text-sm text-green-400" />
              </div>
            ) : (
              <div className='mt-1'>
                <CheckCircle className="min-w-min text-sm text-zinc-600" />
              </div>
            )

            }
            <p>
              {item.description}
            </p>
          </li>
        ))}
      </ul>
    </div>
  );
}
