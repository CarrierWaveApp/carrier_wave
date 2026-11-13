import { tokens } from '../styles/tokens';

interface FavoriteButtonProps {
  isFavorited: boolean;
  onClick: (e: React.MouseEvent) => void;
}

export function FavoriteButton({ isFavorited, onClick }: FavoriteButtonProps) {
  return (
    <button
      onClick={onClick}
      style={{
        background: 'none',
        border: 'none',
        cursor: 'pointer',
        padding: '0.25rem',
        fontSize: '1rem',
        lineHeight: 1,
        color: isFavorited ? '#fbbf24' : tokens.color.textTertiary,
        transition: 'color 0.15s',
      }}
      title={isFavorited ? 'Remove from favorites' : 'Add to favorites'}
    >
      {isFavorited ? '\u2605' : '\u2606'}
    </button>
  );
}
