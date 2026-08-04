import { render, screen } from '@testing-library/react';
import Cart from '../cart/page';

describe('Cart page', () => {
    beforeEach(() => {
        localStorage.clear();
    });

    afterEach(() => {
        jest.resetAllMocks();
    });

    it('renders the empty-cart state when there are no items', () => {
        // No user in localStorage -> effect does not fetch, cart stays empty
        render(<Cart />);
        expect(screen.getByText(/your cart is empty/i)).toBeInTheDocument();
        expect(
            screen.getByRole('link', { name: /browse products/i })
        ).toHaveAttribute('href', '/catalogue');
    });

    it('renders items and computes line subtotals and the cart total', async () => {
        localStorage.setItem('user', JSON.stringify({ id: 5 }));
        global.fetch = jest.fn(() =>
            Promise.resolve({
                json: () =>
                    Promise.resolve({
                        items: [
                            { productId: 1, name: 'Servo', sku: 'SV1', price: 10, quantity: 2 },
                            { productId: 2, name: 'Sensor', sku: 'SN2', price: 5.5, quantity: 3 },
                        ],
                    }),
            })
        );

        render(<Cart />);

        // Item names appear once the cart resolves
        expect(await screen.findByText('Servo')).toBeInTheDocument();
        expect(screen.getByText('Sensor')).toBeInTheDocument();

        // Subtotal for line 1 = 10 * 2 = 20.00
        expect(screen.getByText('$20.00')).toBeInTheDocument();
        // Subtotal for line 2 = 5.5 * 3 = 16.50
        expect(screen.getByText('$16.50')).toBeInTheDocument();

        // Grand total = 20 + 16.5 = 36.50
        expect(screen.getByText('$36.50')).toBeInTheDocument();

        expect(global.fetch).toHaveBeenCalledWith('/api/cart/5');
    });
});
